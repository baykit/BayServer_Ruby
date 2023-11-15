require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/docker/ajp/command/package'
require 'baykit/bayserver/util/string_util'

require 'baykit/bayserver/docker/ajp/ajp_protocol_handler'


module Baykit
  module BayServer
    module Docker
      module Ajp
        class AjpWarpHandler < Baykit::BayServer::Docker::Ajp::AjpProtocolHandler
          include Baykit::BayServer::Docker::Warp::WarpHandler # implements

          class WarpProtocolHandlerFactory
            include Baykit::BayServer::Protocol::ProtocolHandlerFactory  # implements

            def create_protocol_handler(pkt_store)
              return AjpWarpHandler.new(pkt_store)
            end
          end


          include Baykit::BayServer::Agent
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Docker::Warp
          include Baykit::BayServer::Docker::Ajp::Command
          include Baykit::BayServer::Util

          FIXED_WARP_ID = 1

          STATE_READ_HEADER = 1
          STATE_READ_CONTENT = 2

          attr :state

          attr :cont_read_len

          def initialize(pkt_store)
            super(pkt_store, false)
            reset()
          end

          def reset()
            super
            reset_state()
            @cont_read_len = 0
          end

          def to_s()
            return ship().to_s()
          end

          ######################################################
          # Implements WarpHandler
          ######################################################
          def next_warp_id()
            return 1
          end

          def new_warp_data(warp_id)
            return WarpData.new(ship, warp_id)
          end

          def post_warp_headers(tur)
            send_forward_request(tur)
          end

          def post_warp_contents(tur, buf, start, len, &callback)
            send_data(tur, buf, start, len, &callback)
          end

          def post_warp_end(tur)
            callback = lambda do
              @ship.agent.non_blocking_handler.ask_to_read(@ship.socket)
            end
            @ship.post(nil, callback)
          end

          def verify_protocol(proto)
          end

          ######################################################
          # Implements AjpCommandHandler
          ######################################################
          def handle_data(cmd)
            raise ProtocolException.new("Invalid AJP command: %d", cmd.type)
          end

          def handle_end_response(cmd)
            BayLog.debug("%s handle_end_response reuse=%s", @ship, cmd.reuse)
            tur = @ship.get_tour(FIXED_WARP_ID)

            if @state == STATE_READ_HEADER
              end_res_header(tur)
            end

            end_res_content(tur)
            if cmd.reuse
              return NextSocketAction::CONTINUE
            else
              return NextSocketAction::CLOSE
            end

          end

          def handle_forward_request(cmd)
            raise ProtocolException.new("Invalid AJP command: #{cmd.type}")
          end

          def handle_send_body_chunk(cmd)
            BayLog.debug("%s handle_send_body_chunk: len=%d", @ship, cmd.length)
            tur = @ship.get_tour(FIXED_WARP_ID)

            if @state == STATE_READ_HEADER

              sid = @ship.ship_id
              tur.res.set_consume_listener do |len, resume|
                if resume
                  @ship.resume(sid)
                end
              end

              end_res_header(tur)
            end

            available = tur.res.send_content(tur.tour_id, cmd.chunk, 0, cmd.length)
            @cont_read_len += cmd.length

            if available
              return NextSocketAction::CONTINUE
            else
              return NextSocketAction::SUSPEND
            end
          end

          def handle_send_headers(cmd)
            BayLog.debug("%s handle_send_headers", @ship)

            tur = @ship.get_tour(FIXED_WARP_ID)

            if @state != STATE_READ_HEADER
              raise ProtocolException.new("Invalid AJP command: %d state=%s", cmd.type, @state)
            end

            wdat = WarpData.get(tur)

            if BayServer.harbor.trace_header?
              BayLog.info("%s recv res status: %d", wdat, cmd.status)
            end

            wdat.res_headers.status = cmd.status
            cmd.headers.keys.each do |name|
              cmd.headers[name].each do |value|
                if BayServer.harbor.trace_header?
                  BayLog.info("%s recv res header: %s=%s", wdat, name, value)
                end
                wdat.res_headers.add(name, value)
              end
            end

            return NextSocketAction::CONTINUE
          end

          def handle_shutdown(cmd)
            raise ProtocolException.new("Invalid AJP command: %d", cmd.type)
          end

          def handle_get_body_chunk(cmd)
            BayLog.debug("%s handle_get_body_chunk", self)
            return NextSocketAction::CONTINUE
          end

          def handle_eof
            raise EOFError.new()
          end

          def need_data
            return false
          end

          private
          def end_res_header(tur)
            wdat = WarpData.get(tur)
            wdat.res_headers.copy_to(tur.res.headers)
            tur.res.send_headers(Tour::TOUR_ID_NOCHECK)
            change_state(STATE_READ_CONTENT)
          end

          def end_res_content(tur)
            @ship.end_warp_tour(tur)
            tur.res.end_content(Tour::TOUR_ID_NOCHECK)
            reset_state()
          end

          def change_state(new_state)
            @state = new_state
          end

          def reset_state
            change_state(STATE_READ_HEADER)
          end


          def send_forward_request(tur)
            BayLog.debug("%s construct header", tur)

            cmd = CmdForwardRequest.new()
            cmd.to_server = true
            cmd.method = tur.req.method
            cmd.protocol = tur.req.protocol
            rel_uri = tur.req.rewritten_uri != nil ? tur.req.rewritten_uri : tur.req.uri
            town_path = tur.town.name
            if !town_path.end_with?("/")
              town_path += "/"
            end

            rel_uri = rel_uri[town_path.length .. -1]
            req_uri = @ship.docker.warp_base + rel_uri

            pos = req_uri.index('?')
            if pos != nil
              cmd.req_uri = req_uri[0 .. pos - 1]
              cmd.attributes["?query_string"] = req_uri[pos + 1 .. -1]
            else
              cmd.req_uri = req_uri
            end

            cmd.remote_addr = tur.req.remote_address
            cmd.remote_host = tur.req.remote_host()
            cmd.server_name = tur.req.server_name
            cmd.server_port = @ship.docker.port
            cmd.is_ssl = tur.is_secure
            cmd.headers = tur.req.headers
            if BayServer.harbor.trace_header?
              cmd.headers.names.each do |name|
                cmd.headers.values(name).each do |value|
                  BayLog.info("%s sendWarpHeader: %s=%s", WarpData.get(tur), name, value)
                end
              end
            end

            @ship.post(cmd)
          end

          def send_data(tur, data, ofs, len, &callback)
            BayLog.debug("%s construct contents", tur)

            cmd = CmdData.new(data, ofs, len)
            cmd.to_server = true

            @ship.post(cmd, &callback)
          end

        end
      end
    end
  end
end

