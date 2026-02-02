require 'baykit/bayserver/common/inbound_handler'
require 'baykit/bayserver/tours/req_content_handler'

require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/http_util'
require 'baykit/bayserver/docker/ajp/ajp_protocol_handler'
require 'baykit/bayserver/docker/ajp/ajp_handler'
require 'baykit/bayserver/docker/ajp/command/package'

module Baykit
  module BayServer
    module Docker
      module Ajp
        class AjpInboundHandler

          class InboundProtocolHandlerFactory
            include Baykit::BayServer::Protocol::ProtocolHandlerFactory  # implements
            include Baykit::BayServer::Protocol

            def create_protocol_handler(pkt_store)
              ib_handler = AjpInboundHandler.new
              cmd_unpacker = AjpCommandUnPacker.new(ib_handler)
              pkt_unpacker = AjpPacketUnPacker.new(pkt_store, cmd_unpacker)
              pkt_packer = PacketPacker.new()
              cmd_packer = CommandPacker.new(pkt_packer, pkt_store)

              proto_handler = AjpProtocolHandler.new(ib_handler, pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, true)
              ib_handler.init(proto_handler)
              return proto_handler
            end
          end

          include Baykit::BayServer::Common::InboundHandler # implements
          include Baykit::BayServer::Docker::Ajp::AjpHandler # implements

          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Docker::Ajp::Command

          STATE_READ_FORWARD_REQUEST = :FORWARD_REQUEST
          STATE_READ_DATA = :READ_DATA

          DUMMY_KEY = 1
          attr :cur_tour_id
          attr :req_command
          attr :protocol_handler

          attr :state
          attr :keeping

          def initialize
            reset
          end

          def init(proto_handler)
            @protocol_handler = proto_handler
          end

          ######################################################
          # implements Reusable
          ######################################################
          def reset
            reset_state()
            @req_command = nil
            @keeping = false
            @cur_tour_id = 0
          end

          ######################################################
          # implements InboundHandler
          ######################################################
          def send_res_headers(tur)
            chunked = false
            cmd = CmdSendHeaders.new()
            tur.res.headers.names.each do |name|
              tur.res.headers.values(name).each do |value|
                cmd.add_header(name, value)
              end
            end
            cmd.status = tur.res.headers.status
            @protocol_handler.post(cmd)

            BayLog.debug("%s send header: content-length=%d", self, tur.res.headers.content_length())
          end

          def send_res_content(tur, bytes, ofs, len, &lis)
            cmd = CmdSendBodyChunk.new(bytes, ofs, len);
            @protocol_handler.post(cmd, &lis);
          end

          def send_end_tour(tur, &callback)
            BayLog.debug("%s endTour: tur=%s", ship, tur)
            cmd = CmdEndResponse.new()
            cmd.reuse = true  # Always reuse connection

            ensure_func = lambda do
              if !cmd.reuse
                ship.post_close
              end
            end

            begin
              @protocol_handler.post(cmd) do
                BayLog.debug("%s call back in sendEndTour: tur=%s", self, tur)
                ensure_func.call()
                callback.call()
              end
            rescue IOError => e
              BayLog.debug("%s post failed in sendEndTour: tur=%s", self, tur)
              ensure_func.call()
              raise e
            end
          end

          def on_protocol_error(e)
            tur = ship.get_error_tour()
            tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::BAD_REQUEST, e.message, e)
            return true
          end


          ######################################################
          # implements AjpCommandHandler
          ######################################################
          def handle_forward_request(cmd)
            BayLog.debug("%s handleForwardRequest method=%s uri=%s", ship, cmd.method, cmd.req_uri)
            if @state != STATE_READ_FORWARD_REQUEST
              raise ProtocolException.new("Invalid AJP command: #{cmd.type}")
            end

            @keeping = false
            @req_command = cmd
            tur = ship.get_tour(DUMMY_KEY)
            if tur == nil
              BayLog.error(BayMessage.get(:INT_NO_MORE_TOURS))
              tur = ship.get_tour(AjpInboundHandler::DUMMY_KEY, true)
              tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::SERVICE_UNAVAILABLE, "No available tours")
              tur.res.end_content(Tour::TOUR_ID_NOCHECK)
              return NextSocketAction::CONTINUE
            end

            @cur_tour_id = tur.id
            tur.req.uri = cmd.req_uri
            tur.req.protocol = cmd.protocol
            tur.req.method = cmd.method
            cmd.headers.copy_to(tur.req.headers)
            query_string = cmd.attributes["?query_string"]

            if StringUtil.set?(query_string)
              tur.req.uri += "?" + query_string
            end

            BayLog.debug("%s read header method=%s protocol=%s uri=%s contlen=%d",
                         tur, tur.req.method, tur.req.protocol, tur.req.uri, tur.req.headers.content_length)

            if BayServer.harbor.trace_header
              cmd.headers.names.each do |name|
                cmd.headers.values(name).each do |value|
                  BayLog.info("%s header: %s=%s", tur, name, value)
                end
              end
            end

            req_cont_len = cmd.headers.content_length
            if req_cont_len > 0
              tur.req.set_limit(req_cont_len)
            end

            begin
              start_tour(tur)

              if req_cont_len <= 0
                end_req_content(tur)
              else
                change_state(STATE_READ_DATA)
              end

              return NextSocketAction::CONTINUE
            rescue HttpException => e
              if req_cont_len <= 0
                tur.res.send_http_exception(Tour::TOUR_ID_NOCHECK, e)
                reset_state()
                return NextSocketAction::WRITE
              else
                # Delay send
                change_state(STATE_READ_DATA)
                tur.error = e
                tur.req.set_content_handler(ReqContentHandler::DEV_NULL)
                return NextSocketAction::CONTINUE
              end
            end
          end

          def handle_data(cmd)
            BayLog.debug("%s handleData len=%s", ship, cmd.length)

            if @state != STATE_READ_DATA
              raise RuntimeError.new("Invalid AJP command: #{cmd.type} state=#{@state}")
            end

            tur = ship.get_tour(DUMMY_KEY)

            begin
              sid = ship.ship_id
              success = tur.req.post_req_content(Tour::TOUR_ID_NOCHECK, cmd.data, cmd.start, cmd.length) do |len, resume|
                if resume
                  ship.resume(sid)
                end
              end

              if tur.req.bytes_posted == tur.req.bytes_limit
                # request content completed

                if tur.error != nil
                  tur.res.send_http_exception(Tour::TOUR_ID_NOCHECK, tur.error)
                  reset_state()
                  return NextSocketAction::WRITE
                else
                  end_req_content(tur)
                  return NextSocketAction::CONTINUE
                end
              else
                bch = CmdGetBodyChunk.new()
                bch.req_len = tur.req.bytes_limit - tur.req.bytes_posted
                if bch.req_len > AjpPacket::MAX_DATA_LEN
                  bch.req_len = AjpPacket::MAX_DATA_LEN
                end
                @protocol_handler.post(bch)

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

          def handle_send_body_chunk(cmd)
            raise RuntimeError.new "Invalid AJP command: #{cmd.type}"
          end

          def handle_send_headers(cmd)
            raise RuntimeError.new "Invalid AJP command: #{cmd.type}"
          end

          def handle_shutdown(cmd)
            BayLog.info("%s handle_shutdown", ship)
            BayServer.shutdown
            NextSocketAction::CLOSE
          end

          def handle_end_response(cmd)
            raise RuntimeError.new "Invalid AJP command: #{cmd.type}"
          end

          def handle_get_body_chunk(cmd)
            raise RuntimeError.new "Invalid AJP command: #{cmd.type}"
          end

          def need_data()
            return @state == STATE_READ_DATA
          end

          private

          def ship
            return @protocol_handler.ship
          end

          def reset_state
            change_state(STATE_READ_FORWARD_REQUEST)
          end

          def change_state(new_state)
            @state = new_state
          end

          def end_req_content(tur)
            tur.req.end_req_content(Tour::TOUR_ID_NOCHECK)
            reset_state()
          end

          def start_tour(tur)
            HttpUtil.parse_host_port(tur, @req_command.is_ssl ? 443 : 80)
            HttpUtil.parse_authorization(tur)

            skt = ship.rudder.io
            tur.req.remote_port = nil
            tur.req.remote_address = @req_command.remote_addr
            tur.req.remote_host_func = lambda { @req_command.remote_host }

            tur.req.server_address = skt.local_address.ip_address
            tur.req.server_port = @req_command.server_port
            tur.req.server_name = @req_command.server_name
            tur.is_secure = @req_command.is_ssl

            tur.go()
          end


        end
      end
    end
  end
end
