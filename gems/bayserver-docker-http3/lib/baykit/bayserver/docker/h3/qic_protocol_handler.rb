require 'croute'

require 'baykit/bayserver/docker/h3/command/cmd_header'
require 'baykit/bayserver/docker/h3/command/cmd_data'
require 'baykit/bayserver/docker/h3/command/cmd_finished'

module Baykit
  module BayServer
    module Docker
      module H3
        class QicProtocolHandler

          MAX_DATAGRAM_SIZE = 1350
          PROTOCOL = "HTTP/3"

          # PartialResponse holds buffered send data for a stream that was
          # blocked (H3_ERR_STREAM_BLOCKED or zero capacity).
          class PartialResponse
            attr_accessor :headers, :body, :written, :fin, :listener, :finished

            # headers-only: PartialResponse.new(headers: [...])
            # body data:    PartialResponse.new(body: buf, written: ofs, listener: lis)
            # end-of-stream:PartialResponse.new(fin: true, listener: lis)
            def initialize(headers: nil, body: nil, written: 0, fin: false, listener: nil)
              @headers  = headers
              @body     = body ? body.byteslice(written, body.bytesize - written) : nil
              @written  = 0
              @fin      = fin
              @listener = listener
              @finished = false
            end
          end

          attr_accessor :ship
          attr_reader   :con, :h3con, :sender, :local_addr, :peer_addr
          attr_reader   :partial_responses, :h3_config, :multiplexer
          attr_reader   :inbound_handler

          def initialize(inbound_handler, con, sender_addr, local_addr, peer_addr, h3_config, multiplexer)
            @inbound_handler  = inbound_handler
            @con              = con
            @sender           = sender_addr  # Addrinfo or [ip, port] from recvfrom
            @local_addr       = local_addr   # Croute::Quic::Address
            @peer_addr        = peer_addr    # Croute::Quic::Address
            @h3_config        = h3_config
            @multiplexer      = multiplexer
            @h3con            = nil
            @partial_responses = {}           # stm_id => Array<PartialResponse>
            @send_scratch      = ("\0".b * MAX_DATAGRAM_SIZE)
            @send_info         = Croute::Binding.new_send_info
          end

          def init(ship)
            @ship = ship
          end

          def to_s
            @ship ? @ship.to_s : "h3"
          end

          def protocol
            PROTOCOL
          end

          # Called by InboundShip#notify_read with raw UDP datagram bytes.
          def bytes_received(buf)
            n = begin
              @con.recv(buf, @peer_addr, @local_addr)
            rescue Croute::Error => e
              BayLog.debug("%s recv rejected: %s (code=%d)", self, e.message, e.code)
              return Baykit::BayServer::Agent::NextSocketAction::CONTINUE
            end

            if n == Croute::Binding::ERR_DONE
              BayLog.debug("%s No data", self)
            else
              h3c = http3_connection
              process_h3_connection(h3c) if h3c
            end

            Baykit::BayServer::Agent::NextSocketAction::CONTINUE
          end

          def http3_connection
            if @h3con.nil?
              if @con.early_data? || @con.established?
                BayLog.debug("%s Handshake done", self)
                @h3con = Croute::H3::Connection.new(@con, config: @h3_config)
                BayLog.debug("%s New H3 connection", self)
              end
            end
            @h3con
          end

          def process_h3_connection(h3c)
            BayLog.trace("%s processH3Connection", self)
            begin
              while (ev = h3c.poll)
                dispatch_event(ev)
              end
            rescue Croute::Error => e
              BayLog.debug("%s h3 poll failed: %s (code=%d)", self, e.message, e.code)
            end
            flush_writable
          end

          def dispatch_event(ev)
            stm_id = ev.stream_id
            case ev.type
            when :headers
              @inbound_handler.handle_headers(Command::CmdHeader.new(stm_id, ev.headers))
            when :data
              @inbound_handler.handle_data(Command::CmdData.new(stm_id))
            when :finished
              @inbound_handler.handle_finished(Command::CmdFinished.new(stm_id))
            else
              BayLog.debug("%s stm#%d ignored event: %s", self, stm_id, ev.type)
            end
          end

          def flush_writable
            @con.writable_streams.each do |stm_id|
              on_stream_writable(stm_id)
            end
          end

          def on_stream_writable(stm_id)
            parts = @partial_responses[stm_id]
            return unless parts

            BayLog.debug("%s stm#%d writable qlen=%d", self, stm_id, parts.size)
            listeners = nil

            begin
              parts.each do |part|
                cap = begin
                  @con.stream_capacity(stm_id)
                rescue Croute::Error => e
                  if e.code == Croute::Error::ERR_STREAM_STOPPED
                    BayLog.debug("stm#%d writable, but stream stopped", stm_id)
                    break
                  end
                  raise IOException, "stm##{stm_id} writable error: #{e.message}"
                end

                BayLog.trace("stm#%d writable capacity=%d", stm_id, cap)
                if cap == 0
                  BayLog.debug("stm#%d writable, but no capacity", stm_id)
                  break
                end

                if part.headers
                  begin
                    @h3con.send_response(stm_id, part.headers, part.fin)
                  rescue Croute::Error => e
                    if e.code == Croute::Error::H3_ERR_STREAM_BLOCKED
                      BayLog.debug("%s stm#%d retry to send header: blocked", self, stm_id)
                      break
                    elsif e.code == Croute::Error::H3_ERR_TRANSPORT_ERROR
                      raise IOError, "stm##{stm_id} h3: send header failed (transport)"
                    else
                      raise IOError, "stm##{stm_id} h3: send header failed: #{e.message}(#{e.code})"
                    end
                  end
                  BayLog.debug("%s stm#%d h3: retry to send header succeed", self, stm_id)
                  part.finished = true
                else
                  body = part.body ? part.body.byteslice(part.written, part.body.bytesize - part.written) : "".b
                  n = begin
                    @h3con.send_body(stm_id, body, part.fin)
                  rescue Croute::Error => e
                    BayLog.error("%s stm#%d h3: retry to send body failed: %s(%d)", self, stm_id, e.message, e.code)
                    break
                  end

                  BayLog.trace("%s stm#%d retry to send body %d bytes fin=%s", self, stm_id, n, part.fin)
                  if n == 0
                    BayLog.debug("%s stm#%d retry to send body: DONE returned (retry)", self, stm_id)
                    break
                  else
                    part.written += n
                    part.finished = true if part.written >= (part.body ? part.body.bytesize : 0)
                    break unless part.finished
                  end
                end
              end

              # Remove finished parts from the front of the queue.
              # Stop at the first unfinished part (ordering must be preserved).
              while !parts.empty? && parts.first.finished
                part = parts.shift
                if part.listener
                  listeners ||= []
                  listeners << part.listener
                end
              end

            rescue => e
              BayLog.error_e(e)
              parts.clear
            end

            listeners&.each { |lis| lis.call(true) }

            @partial_responses.delete(stm_id) if parts.empty?

            post_packets
          end

          def add_partial_response(stm_id, part)
            @partial_responses[stm_id] ||= []
            @partial_responses[stm_id] << part
          end

          # Send all queued QUIC packets onto the UDP socket.
          def post_packets
            posted = false
            loop do
              break if @con.closed?
              n = begin
                @con.send(@send_scratch, @send_info)
              rescue Croute::Error => e
                BayLog.debug("%s send on closing connection: %s", self, e.message)
                break
              end
              break if n == Croute::Binding::ERR_DONE

              pkt = @send_scratch.byteslice(0, n).b
              @multiplexer.req_write(@ship.rudder, pkt, 0, n, @sender, pkt, true) {}
              posted = true
            end
            posted
          end

          def closed?
            @con.closed?
          end

          def peer_or_local_error_code
            -1
          end

          def reset
            @h3con = nil
            @partial_responses.clear
          end
        end
      end
    end
  end
end
