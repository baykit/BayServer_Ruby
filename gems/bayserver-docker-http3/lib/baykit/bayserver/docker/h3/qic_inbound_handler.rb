require 'croute'

require 'baykit/bayserver/docker/h3/qic_protocol_handler'
require 'baykit/bayserver/docker/h3/command/cmd_header'
require 'baykit/bayserver/docker/h3/command/cmd_data'
require 'baykit/bayserver/docker/h3/command/cmd_finished'

module Baykit
  module BayServer
    module Docker
      module H3
        class QicInboundHandler

          # RFC 9114 §8.1 — H3_MESSAGE_ERROR application error code
          H3_MESSAGE_ERROR = 0x10e

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Util

          attr_accessor :protocol_handler

          def initialize
            @protocol_handler = nil
          end

          def init(proto_handler)
            @protocol_handler = proto_handler
          end

          def reset
          end

          ##############################################################
          # InboundHandler — send side (server → client)
          ##############################################################

          def send_headers(tur)
            stm_id = tur.req.key
            BayLog.debug("%s stm#%d sendResHeader", tur, stm_id)

            headers = [[":status", tur.res.headers.status.to_s]]
            tur.res.headers.header_names.each do |name|
              tur.res.headers.header_values(name).each do |value|
                headers << [name, value]
              end
            end

            if BayServer.harbor.trace_header
              headers.each do |name, value|
                BayLog.info("%s stm#%d header %s: %s", tur, stm_id, name, value)
              end
            end

            begin
              @protocol_handler.h3con.send_response(stm_id, headers, false)
              @protocol_handler.post_packets
            rescue Croute::Error => e
              if e.code == Croute::Error::H3_ERR_STREAM_BLOCKED
                BayLog.warn("%s stm#%d sending header is blocked", tur, stm_id)
                @protocol_handler.add_partial_response(
                  stm_id,
                  QicProtocolHandler::PartialResponse.new(headers: headers))
              elsif e.code == Croute::Error::H3_ERR_TRANSPORT_ERROR
                raise IOError, "h3: send header failed (transport)"
              else
                raise IOError, "h3: send header failed: #{e.message}(#{e.code})"
              end
            end
          end

          def send_content(tur, bytes, ofs, len, &lis)
            stm_id = tur.req.key
            BayLog.debug("%s stm#%d sendResContent len=%d", tur, stm_id, len)

            buf = (ofs > 0 || len < bytes.bytesize) ? bytes.byteslice(ofs, len) : bytes
            part = nil

            if @protocol_handler.partial_responses.key?(stm_id)
              BayLog.trace("%s stm#%d waiting. put packet into queue len=%d", tur, stm_id, len)
              part = QicProtocolHandler::PartialResponse.new(body: buf, listener: lis)
            else
              cap = begin
                @protocol_handler.con.stream_capacity(stm_id)
              rescue Croute::Error => e
                if e.code == Croute::Error::ERR_STREAM_STOPPED
                  BayLog.error("%s stm#%d Stream stopped", tur, stm_id)
                  part = QicProtocolHandler::PartialResponse.new(body: buf, listener: lis)
                  -1
                else
                  raise quiche_error("Get capacity failed: ", stm_id, e.code)
                end
              end

              if part.nil?
                if cap == 0
                  part = QicProtocolHandler::PartialResponse.new(body: buf, listener: lis)
                else
                  written = begin
                    @protocol_handler.h3con.send_body(stm_id, buf, false)
                  rescue Croute::Error => e
                    if e.code == Croute::Error::H3_ERR_FRAME_UNEXPECTED
                      part = QicProtocolHandler::PartialResponse.new(body: buf, listener: lis)
                    elsif e.code == Croute::Error::H3_ERR_TRANSPORT_ERROR
                      raise IOError, "h3: send body failed (transport)"
                    else
                      raise IOError, "h3: send body failed: #{e.message}(#{e.code})"
                    end
                  end

                  if part.nil?
                    BayLog.debug("stm#%d send %d/%d bytes body", stm_id, written, len)
                    if written == 0
                      part = QicProtocolHandler::PartialResponse.new(body: buf, listener: lis)
                    elsif written < len
                      part = QicProtocolHandler::PartialResponse.new(
                        body: buf.byteslice(written, buf.bytesize - written),
                        listener: lis)
                    end
                  end
                end
              end
            end

            if part
              @protocol_handler.add_partial_response(stm_id, part)
            else
              lis&.call(true)
            end

            @protocol_handler.post_packets
            true
          end

          def send_end_tour(tur, &lis)
            stm_id = tur.req.key
            BayLog.debug("%s stm#%d sendEndTour", tur, stm_id)
            retry_flag = false

            if @protocol_handler.partial_responses.key?(stm_id)
              BayLog.debug("stm#%d put packet into queue (end)", stm_id)
              retry_flag = true
            else
              cap = begin
                @protocol_handler.con.stream_capacity(stm_id)
              rescue Croute::Error => e
                case e.code
                when Croute::Error::ERR_STREAM_STOPPED
                  BayLog.error("%s stm#%d Stream stopped", tur, stm_id)
                  retry_flag = true
                  -1
                when Croute::Error::ERR_INVALID_STREAM_STATE
                  BayLog.error("%s stm#%d Invalid stream (ignore)", tur, stm_id)
                  -1
                else
                  raise quiche_error("Cannot get capacity: ", stm_id, e.code)
                end
              end

              unless retry_flag
                if cap == 0
                  BayLog.debug("%s stm#%d stream full, retry", tur, stm_id)
                  retry_flag = true
                else
                  begin
                    @protocol_handler.h3con.send_body(stm_id, "".b, true)
                    BayLog.debug("stm#%d send finish", stm_id)
                  rescue Croute::Error => e
                    if e.code == Croute::Error::H3_ERR_FRAME_UNEXPECTED
                      BayLog.warn("stm#%d send end content error Frame Unexpected", stm_id)
                      retry_flag = true
                    elsif e.code == Croute::Error::H3_ERR_TRANSPORT_ERROR
                      raise IOError, "h3: send body failed (transport)"
                    else
                      raise IOError, "h3: send body failed: #{e.message}(#{e.code})"
                    end
                  end
                end
              end
            end

            if retry_flag
              @protocol_handler.add_partial_response(
                stm_id,
                QicProtocolHandler::PartialResponse.new(fin: true, listener: lis))
            else
              lis&.call(true)
            end

            @protocol_handler.post_packets
          end

          ##############################################################
          # Command handlers — receive side (client → server)
          ##############################################################

          def handle_headers(cmd)
            stm_id = cmd.stm_id
            BayLog.debug("%s stm#%d onHeaders", self, stm_id)

            begin
              tur = get_tour(stm_id)
              if tur.nil?
                tour_is_unavailable(stm_id)
                return
              end

              unless validate_pseudo_headers(cmd, stm_id)
                close_with_h3_error(H3_MESSAGE_ERROR, "malformed pseudo-headers")
                return
              end

              cmd.req_headers.each do |name, value|
                BayLog.info("%s stm#%d ReqHeader %s=%s", tur, stm_id, name, value) if BayServer.harbor.trace_header
                case name.downcase
                when ":path"
                  tur.req.uri = value
                when ":authority"
                  tur.req.headers.add(Headers::HOST, value)
                when ":scheme"
                  tur.is_secure = value.casecmp("https") == 0
                when ":method"
                  tur.req.method = value
                else
                  tur.req.headers.add(name, value) unless name.start_with?(":")
                end
              end

              BayLog.debug("%s stm#%d onHeader: method=%s uri=%s", tur, stm_id, tur.req.method, tur.req.uri)

              req_cont_len = tur.req.headers.content_length
              tur.req.set_limit(req_cont_len) if req_cont_len > 0

              begin
                start_tour(tur)
                if tur.req.headers.content_length <= 0
                  end_req_content(tur.id, tur)
                end
              rescue HttpException => e
                BayLog.debug("%s Http error occurred: %s", self, e)
                if req_cont_len <= 0
                  tur.res.send_http_exception(Tour::TOUR_ID_NOCHECK, e)
                else
                  tur.error = e
                  tur.req.set_req_content_handler(ReqContentHandler::DEV_NULL)
                end
              end
            rescue => e
              BayLog.error_e(e)
            end
          end

          def handle_data(cmd)
            stm_id = cmd.stm_id
            BayLog.debug("%s stm#%d onData", self, stm_id)

            begin
              tur = get_tour(stm_id)
              if tur.nil?
                tour_is_unavailable(stm_id)
                return
              end

              buf = "\0".b * QicProtocolHandler::MAX_DATAGRAM_SIZE
              n_read = begin
                @protocol_handler.h3con.recv_body(stm_id, buf)
              rescue Croute::Error => e
                BayLog.error("%s stm#%d h3: recv body failed: %s(%d)", self, stm_id, e.message, e.code)
                return
              end

              if n_read != Croute::Binding::H3_ERR_DONE && n_read > 0
                sid = @protocol_handler.ship.ship_id
                tur.req.post_req_content(
                  Tour::TOUR_ID_NOCHECK,
                  buf, 0, n_read.to_i,
                  ->(length, resume) { tur.ship.resume_read(sid) if resume }
                )
              end

              if tur.req.bytes_posted >= tur.req.headers.content_length
                if tur.error
                  tur.res.send_http_exception(Tour::TOUR_ID_NOCHECK, tur.error)
                else
                  begin
                    end_req_content(tur.id, tur)
                  rescue HttpException => e
                    tur.res.send_http_exception(Tour::TOUR_ID_NOCHECK, e)
                  end
                end
              end
            rescue => e
              BayLog.error_e(e)
            end
          end

          def handle_finished(cmd)
            BayLog.debug("%s stm#%d onFinished.", self, cmd.stm_id)
          end

          def on_protocol_error(e)
            BayLog.debug_e(e)
            false
          end

          ##############################################################
          # Private helpers
          ##############################################################

          private

          def get_tour(stm_id)
            @protocol_handler.ship.get_tour(stm_id.to_i)
          end

          def tour_is_unavailable(stm_id)
            BayLog.error(BayMessage.get(:INT_NO_MORE_TOURS))
            tur = @protocol_handler.ship.get_tour(stm_id.to_i, true)
            tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::SERVICE_UNAVAILABLE, "No available tours")
          end

          def end_req_content(check_id, tur)
            BayLog.debug("%s endReqContent", tur)
            @protocol_handler.con.stream_shutdown(
              tur.req.key, Croute::Binding::SHUTDOWN_READ, 0)
            tur.req.end_req_content(check_id)
          end

          def start_tour(tur)
            HttpUtil.parse_host_port(tur, 443)
            HttpUtil.parse_authorization(tur)

            tur.req.protocol       = QicProtocolHandler::PROTOCOL
            tur.req.remote_port    = @protocol_handler.peer_addr.port
            tur.req.remote_address = @protocol_handler.peer_addr.ip
            tur.req.remote_host_func = -> { HttpUtil.resolve_remote_host(tur.req.remote_address) }

            tur.req.server_address = @protocol_handler.local_addr.ip
            tur.req.server_port    = tur.req.req_port
            tur.req.server_name    = tur.req.req_host
            tur.is_secure          = true

            tur.go
          end

          # Enforce RFC 9114 §4.3 pseudo-header rules on an inbound request.
          def validate_pseudo_headers(cmd, stm_id)
            seen_pseudo = {}
            saw_regular = false
            method = scheme = path = authority = nil

            cmd.req_headers.each do |name, value|
              if name.empty?
                BayLog.debug("%s stm#%d empty header name", self, stm_id)
                return false
              end
              if name.start_with?(":")
                if saw_regular
                  BayLog.debug("%s stm#%d pseudo-header %s after regular fields", self, stm_id, name)
                  return false
                end
                if seen_pseudo.key?(name)
                  BayLog.debug("%s stm#%d duplicated pseudo-header %s", self, stm_id, name)
                  return false
                end
                seen_pseudo[name] = true
                case name
                when ":method"    then method    = value
                when ":scheme"    then scheme    = value
                when ":path"      then path      = value
                when ":authority" then authority = value
                else
                  BayLog.debug("%s stm#%d prohibited pseudo-header %s", self, stm_id, name)
                  return false
                end
              else
                saw_regular = true
              end
            end

            if method.nil?
              BayLog.debug("%s stm#%d missing :method", self, stm_id)
              return false
            end

            unless method.casecmp("CONNECT") == 0
              if scheme.nil?
                BayLog.debug("%s stm#%d missing :scheme", self, stm_id)
                return false
              end
              if path.nil? || path.empty?
                BayLog.debug("%s stm#%d missing :path", self, stm_id)
                return false
              end
              if authority.nil?
                has_host = cmd.req_headers.any? { |n, _| n.casecmp("host") == 0 }
                unless has_host
                  BayLog.debug("%s stm#%d missing :authority and Host", self, stm_id)
                  return false
                end
              end
            end
            true
          end

          def close_with_h3_error(error_code, reason)
            BayLog.debug("%s closing H3 connection: code=0x%x reason=%s", self, error_code, reason)
            begin
              @protocol_handler.con.close_connection(true, error_code, reason.to_s.b)
            rescue Croute::Error => e
              BayLog.debug("%s closeConnection failed: %s", self, e.message)
            end
            begin
              @protocol_handler.post_packets
            rescue => e
              BayLog.debug("%s postPackets after close failed: %s", self, e.message)
            end
          end

          def quiche_error(msg, stm_id, code)
            IOError.new("stm##{stm_id} #{msg}: #{code}")
          end
        end
      end
    end
  end
end
