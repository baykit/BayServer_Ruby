require 'baykit/bayserver/common/write_unit'
require 'baykit/bayserver/rudders/io_rudder'

require 'baykit/bayserver/agent/multiplexer/multiplexer_base'
require 'baykit/bayserver/agent/multiplexer/job_multiplexer_base'


module Baykit
  module BayServer
    module Agent
      module Multiplexer
        # JobMultiplexer is a reference implementation modelled after the
        # Go version of BayServer, where the runtime cheaply multiplexes a
        # goroutine-per-I/O design. In Ruby every operation spawns a
        # Thread, so GVL contention and context-switch overhead dominate
        # under any meaningful concurrency. Network I/O should use
        # SpiderMultiplexer (nio4r-backed epoll on Linux) instead. This
        # class is retained for cross-language parity, not for production
        # network I/O.
        class JobMultiplexer < JobMultiplexerBase
          include Baykit::BayServer::Agent::TimerHandler #implements
          include Baykit::BayServer::Common::Recipient  # implements
          include Baykit::BayServer::Agent::Multiplexer

          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Util
          include Baykit::BayServer::Common

          def initialize(agt, anchorable)
            super
          end
          def to_s
            return "JobMpx[#{@agent}]"
          end


          #########################################
          # Implements Multiplexer
          #########################################

          def req_accept(rd)
            BayLog.debug("%s reqAccept isShutdown=%s", @agent, @agent.aborted)
            if @agent.aborted
              return
            end

            st = get_rudder_state(rd)
            id = st.id

            Thread.new do
              begin
                if @agent.aborted
                  next
                end

                begin
                  client_skt, adr = rd.io.accept
                rescue Exception => e
                  @agent.send_error_letter(rd, self, e, true)
                  next
                end

                BayLog.debug("%s Accepted skt=%s", @agent, client_skt)
                if agent.aborted
                  BayLog.error("%s Agent is not alive (close)", @agent);
                  client_skt.close
                else
                  @agent.send_accepted_letter(rd, self, IORudder.new(client_skt), true)
                end

              rescue Exception => e
                BayLog.fatal_e(e)
                @agent.shutdown
              end
            end

          end


          def req_connect(rd, adr)
            BayLog.debug("%s reqConnect adr=%s rd=%s", @agent, adr.canonname, rd)

            Thread.new do
              st = get_rudder_state(rd)
              if st == nil
                # rudder is already closed
                BayLog.debug("%s Rudder is already closed: rd=%s", @agent, rd)
                return
              end

              begin
                rd.io.connect(adr)
                BayLog.debug("%s Connected rd=%s", @agent, rd)
                @agent.send_connected_letter(rd, self, true)
              rescue Exception => e
                @agent.send_error_letter(rd, self, e, true)
                return
              end
            end

            st = get_rudder_state(rd)
            st.access
            st.connecting = true
          end

          def req_read(rd)
            st = get_rudder_state(rd)
            if st == nil
              return
            end

            BayLog.debug("%s reqRead rd=%s state=%s", @agent, st.rudder, st);
            need_read = false
            st.reading_lock.synchronize do
              if !st.reading
                need_read = true
                st.reading = true
              end
            end

            if need_read
              next_read(st)
            end

            st.access
          end

          def req_write(rd, buf, ofs, len, adr, tag, flush, &lis)
            st = get_rudder_state(rd)
            BayLog.debug("%s reqWrite st=%s", @agent, st)

            if st == nil
              raise IOError.new("Invalid rudder")
              #BayLog.warn("%s Channel is closed(callback immediately): %s", @agent, rd)
              #lis.call(true)
              #return true
            end

            unt = st.rent_write_unit
            unt.init(buf, ofs, len, adr, tag, &lis)
            st.write_queue_lock.synchronize do
              st.write_queue << unt
            end

            need_write = false
            st.writing_lock.synchronize do
              if !st.writing
                need_write = true
                st.writing = true
              end
            end

            if need_write
              next_write(st)
            end

            st.access
            return st.buffer_available?
          end

          def req_transfer(rd, file_rd, ofs, len, &lis)
            raise Sink.new
          end


          def req_close(rd)
            st = get_rudder_state(rd)
            BayLog.debug("%s reqClose st=%s", @agent, st);

            if st == nil
              BayLog.warn("%s channel state not found: %s", @agent, rd)
              return
            end

            id = st.id

              Thread.new do
              begin
                st = get_rudder_state(rd)
                if st == nil
                  BayLog.debug("%s Rudder is already closed: rd=%s", @agent, rd)
                  next
                end

                close_rudder(rd)
                @agent.send_closed_letter(rd, self, true)
              rescue Exception => e
                BayLog.fatal_e(e)
                @agent.shutdown
              end
            end

            st.access
          end

          def cancel_read(st)

          end

          def cancel_write(st)

          end

          def next_accept(st)
            req_accept(st.rudder)
          end

          def next_read(st)
            id = st.id

            Thread.new do

              begin
                if st.handshaking
                  # Calls accept API for client socket
                  st.rudder.io.accept
                  st.handshaking = false

                  BayLog.debug("%s Handshake done (rd=%s)", self, st.rudder)
                  proto = st.rudder.io.respond_to?(:alpn_protocol) ? st.rudder.io.alpn_protocol : nil
                  BayLog.debug("%s ALPN negotiated: %s", self, proto.inspect)
                  st.transporter.ship.notify_handshake_done(proto)
                end

                BayLog.debug("%s Try to Read (rd=%s)", @agent, st.rudder)
                n = st.rudder.read(st.read_buf, st.buf_size)

                if get_rudder_state(st.rudder) == nil
                  #channel is already closed
                  BayLog.debug("%s Rudder is already closed: rd=%s", self, st.rudder);
                  next
                else
                  @agent.send_read_letter(st.rudder, self, n, nil, true)
                end

              rescue Exception => e
                @agent.send_error_letter(st.rudder, self, e, true)
              end
            end
          end

          def next_write(st)
            id = st.id

            Thread.new do
              BayLog.debug("%s next write st=%s", @agent, st)

              if st == nil
                BayLog.warn("%s Channel is closed: %s", @agent, st.rudder)
                next
              end

              u = st.write_queue[0]
              BayLog.debug("%s Try to write: pkt=%s remaining=%d", self, u.tag, u.remaining)

              n = 0
              begin
                if u.remaining > 0
                  n = st.rudder.write(u.remaining_buf)
                  u.wrote += n
                end
              rescue Exception => e
                @agent.send_error_letter(st.rudder, self, e, true)
                next
              end

              @agent.send_wrote_letter(st.rudder, self, n, true)
            end
          end

          def is_non_blocking()
            return false
          end

          def use_async_api()
            return false
          end
        end
      end
    end
  end
end