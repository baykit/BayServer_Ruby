require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/common/inbound_handler'
require 'baykit/bayserver/tours/req_content_handler'
require 'baykit/bayserver/util/cgi_util'

require 'baykit/bayserver/docker/fcgi/fcg_protocol_handler'
require 'baykit/bayserver/docker/fcgi/fcg_handler'

module Baykit
  module BayServer
    module Docker
      module Fcgi
        class FcgInboundHandler

          class InboundProtocolHandlerFactory
            include Baykit::BayServer::Protocol::ProtocolHandlerFactory  # implements

            include Baykit::BayServer::Protocol

            def create_protocol_handler(pkt_store)
              ib_handler = FcgInboundHandler.new
              cmd_unpacker = FcgCommandUnPacker.new(ib_handler)
              pkt_unpacker = FcgPacketUnPacker.new(pkt_store, cmd_unpacker)
              pkt_packer = PacketPacker.new()
              cmd_packer = CommandPacker.new(pkt_packer, pkt_store)

              proto_handler = FcgProtocolHandler.new(ib_handler, pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, true)
              ib_handler.init(proto_handler)
              return proto_handler
            end
          end

          include Baykit::BayServer::Common::InboundHandler # implements
          include FcgHandler # implements

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Util
          include Baykit::BayServer::Docker::Fcgi::Command

          STATE_BEGIN_REQUEST = 1
          STATE_READ_PARAMS = 2
          STATE_READ_STDIN = 3

          attr :state
          attr :protocol_handler
          attr :cont_len

          attr :env
          attr :req_id
          attr :req_keep_alive

          def initialize
            @env = {}
            reset()
          end

          def init(proto_handler)
            @protocol_handler = proto_handler
          end
          
          def to_s()
            return ClassUtil.get_local_name(self.class)
          end

          ######################################################
          # implements Reusable
          ######################################################
          def reset
            @env.clear()
            reset_state()
          end

          ######################################################
          # implements TourHandler
          ######################################################

          def send_res_headers(tur)
            BayLog.debug("%s PH:sendHeaders: tur=%s", ship, tur)

            scode = tur.res.headers.status
            status = "#{scode} #{HttpStatus.description(scode)}"
            tur.res.headers.set(Headers::STATUS, status)

            if BayServer.harbor.trace_header
              BayLog.info("%s resStatus:%d", tur, tur.res.headers.status)
              tur.res.headers.names().each do |name|
                tur.res.headers.values(name) do |value|
                  BayLog.info("%s resHeader:%s=%s", tur, name, value)
                end
              end
            end

            buf = SimpleBuffer.new
            HttpUtil.send_mime_headers(tur.res.headers, buf)
            HttpUtil.send_new_line(buf)
            cmd = CmdStdOut.new(tur.req.key, buf.buf, 0, buf.length)
            @protocol_handler.post(cmd)
          end

          def send_res_content(tur, bytes, ofs, len, &callback)
            cmd = CmdStdOut.new(tur.req.key, bytes, ofs, len);
            @protocol_handler.post(cmd, &callback)
          end

          def send_end_tour(tur, keep_alive, &callback)
            BayLog.debug("%s PH:endTour: tur=%s keep=%s", ship, tur, keep_alive)

            # Send empty stdout command
            cmd = CmdStdOut.new(tur.req.key)
            @protocol_handler.post(cmd)

            # Send end request command
            cmd = CmdEndRequest.new(tur.req.key)

            ensure_func = lambda do
              # DO NOT close socket by FCGI server
              #if !keep_alive
              #  ship.post_close
              #end
            end

            begin
              @protocol_handler.post(cmd) do
                BayLog.debug("%s call back in sendEndTour: tur=%s keep=%s", self, tur, keep_alive)
                ensure_func.call()
                callback.call()
              end
            rescue IOError => e
              BayLog.debug("%s post failed in sendEndTour: tur=%s keep=%s", self, tur, keep_alive)
              ensure_func.call()
              raise e
            end
          end

          def on_protocol_error(err)
            tur = ship.get_error_tour()
            tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::BAD_REQUEST, err.message, err)
            true
          end

          ######################################################
          # implements FcgCommandHandler
          ######################################################
          def handle_begin_request(cmd)
            sip = ship()
            BayLog.debug("%s handle_begin_request req_id=%d} keep=%s", sip, cmd.req_id, cmd.keep_conn)

            if state != STATE_BEGIN_REQUEST
              raise ProtocolException.new("Invalid FCGI command: %d state=%d", cmd.type, @state)
            end

            check_req_id(cmd.req_id)

            @req_id = cmd.req_id
            BayLog.debug("%s begin_req get_tour req_id=%d", sip, cmd.req_id)
            tur = sip.get_tour(cmd.req_id)
            if tur == nil
              BayLog.error(BayMessage.get(:INT_NO_MORE_TOURS))
              tur = sip.ship.get_tour(cmd.req_id, true)
              tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus.SERVICE_UNAVAILABLE, "No available tours")
              return NextSocketAction::CONTINUE
            end

            @req_keep_alive = cmd.keep_conn
            change_state(STATE_READ_PARAMS)
            NextSocketAction::CONTINUE
          end

          def handle_end_request(cmd)
            raise ProtocolException("Invalid FCGI command: %d", cmd.type)
          end

          def handle_params(cmd)
            BayLog.debug("%s handle_params req_id=%d", ship, cmd.req_id)

            if state != STATE_READ_PARAMS
              raise ProtocolException.new("Invalid FCGI command: %d state=%d", cmd.type, @state)
            end

            check_req_id(cmd.req_id)

            BayLog.debug("%s handle_param get_tour req_id=%d", ship, cmd.req_id)
            tur = ship.get_tour(cmd.req_id)

            if cmd.params.empty?
              # Header completed

              # check keep-alive
              #  keep-alive flag of BeginRequest has high priority
              if @req_keep_alive
                if !tur.req.headers.contains(Headers::CONNECTION)
                  tur.req.headers.set(Headers::CONNECTION, "Keep-Alive")
                else
                  tur.req.headers.set(Headers::CONNECTION, "Close")
                end
              end

              req_cont_len = tur.req.headers.content_length()

              BayLog.debug("%s read header method=%s protocol=%s uri=%s contlen=%d",
                           ship, tur.req.method, tur.req.protocol, tur.req.uri, @cont_len)

              if BayServer.harbor.trace_header
                cmd.params.each do |nv|
                  BayLog.info("%s  reqHeader: %s=%s", tur, nv[0], nv[1])
                end
              end

              if req_cont_len > 0
                tur.req.set_limit(req_cont_len)
              end

              change_state(STATE_READ_STDIN)
              begin
                start_tour(tur)
              rescue HttpException => e
                BayLog.debug("%s Http error occurred: %s", ship, e)

                if req_cont_len <= 0
                  # no post data
                  tur.res.send_http_exception(Tour::TOUR_ID_NOCHECK, e)
                  change_state(STATE_READ_STDIN)
                  return NextSocketAction::CONTINUE
                else
                  # Delay send
                  change_state(STATE_READ_STDIN)
                  tur.error = e
                  tur.req.set_content_handler(ReqContentHandler::DEV_NULL)
                  return NextSocketAction::CONTINUE
                end
              end

            else
              if BayServer.harbor.trace_header
                BayLog.info("%s Read FcgiParam", tur)
              end

              cmd.params.each do |nv|
                name = nv[0]
                value = nv[1]
                if BayServer.harbor.trace_header
                  BayLog.info("%s  param: %s=%s", tur, name, value);
                end
                @env[name] = value

                if name.start_with?("HTTP_")
                  hname = name[5 .. -1]
                  tur.req.headers.add(hname, value)
                elsif name == "CONTENT_TYPE"
                  tur.req.headers.add(Headers::CONTENT_TYPE, value)
                elsif name == "CONTENT_LENGTH"
                  tur.req.headers.add(Headers::CONTENT_LENGTH, value)
                elsif name == "HTTPS"
                  tur.is_secure = value.downcase.casecmp? "on"
                end
              end

              tur.req.uri = @env["REQUEST_URI"]
              tur.req.protocol  = @env["SERVER_PROTOCOL"]
              tur.req.method = @env["REQUEST_METHOD"]

              return NextSocketAction::CONTINUE
            end
          end

          def handle_stderr(cmd)
            raise ProtocolException.new("Invalid FCGI command: %d", cmd.type)
          end

          def handle_stdin(cmd)
            BayLog.debug("%s handle_stdin req_id=%d len=%d", ship, cmd.req_id, cmd.length)

            if @state != STATE_READ_STDIN
              raise ProtocolException.new("Invalid FCGI command: %d state=%d", cmd.type, @state)
            end

            begin
              check_req_id(cmd.req_id)

              tur = ship.get_tour(cmd.req_id)
              if cmd.length == 0
                #  request content completed
                if tur.error != nil
                  # Error has occurred on header completed
                  BayLog.debug("%s Delay send error", tur)
                  raise tur.error
                else
                  begin
                    end_req_content(Tour::TOUR_ID_NOCHECK, tur)
                    return NextSocketAction::CONTINUE
                  end
                end
              else
                sid = ship.ship_id
                success = tur.req.post_req_content(Tour::TOUR_ID_NOCHECK, cmd.data, cmd.start, cmd.length) do |len, resume|
                  if resume
                    ship.resume_read(sid)
                  end
                end

                if !success
                  return NextSocketAction::SUSPEND
                else
                  return NextSocketAction::CONTINUE
                end
              end

            rescue HttpException => e
              tur.req.abort
              tur.res.send_http_exception(Tour::TOUR_ID_NOCHECK, e)
              reset_state()
              return NextSocketAction::WRITE
            end
          end

          def handle_stdout(cmd)
            raise ProtocolException.new("Invalid FCGI command: %d", cmd.type)
          end

          private

          def ship
            return @protocol_handler.ship
          end

          def check_req_id(received_id)
            if received_id == FcgPacket::FCGI_NULL_REQUEST_ID
              raise ProtocolException.new("Invalid request id: %d", received_id)
            end

            if @req_id == FcgPacket::FCGI_NULL_REQUEST_ID
              @req_id = received_id
            end

            if @req_id != received_id
              BayLog.error("%s invalid request id: received=%d reqId=%d", sip, received_id, req_id)
              raise ProtocolException.new("Invalid request id: %d", received_id)
            end
          end

          def change_state(new_state)
            @state = new_state
          end

          def reset_state
            change_state(STATE_BEGIN_REQUEST)
            @req_id = FcgPacket::FCGI_NULL_REQUEST_ID
            @cont_len = 0
          end

          def end_req_content(check_id, tur)
            tur.req.end_req_content(check_id)
            reset_state()
          end

          def start_tour(tur)
            HttpUtil.parse_host_port(tur, tur.is_secure ? 443 : 80)
            HttpUtil.parse_authorization(tur)

            tur.req.remote_port = @env[CgiUtil::REMOTE_PORT].to_i
            tur.req.remote_address = @env[CgiUtil::REMOTE_ADDR]
            tur.req.remote_host_func = lambda { tur.req.remote_address }

            tur.req.server_name = @env[CgiUtil::SERVER_NAME]
            tur.req.server_address = @env[CgiUtil::SERVER_ADDR]
            tur.req.server_port = @env[CgiUtil::SERVER_PORT].to_i


            tur.go
          end

        end
      end
    end
  end
end
