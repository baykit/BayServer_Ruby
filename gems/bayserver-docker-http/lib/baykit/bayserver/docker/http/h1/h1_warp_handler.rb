require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/docker/warp/package'
require 'baykit/bayserver/docker/http/h1/command/package'

module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          class H1WarpHandler < H1ProtocolHandler
            include Baykit::BayServer::Docker::Warp::WarpHandler # implements

            class WarpProtocolHandlerFactory
              include Baykit::BayServer::Protocol::ProtocolHandlerFactory  # implements

              def create_protocol_handler(pkt_store)
                return H1WarpHandler.new(pkt_store)
              end
            end

            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Tours
            include Baykit::BayServer::Agent
            include Baykit::BayServer::Util
            include Baykit::BayServer::Docker::Warp
            include Baykit::BayServer::Docker::Http::H1::Command

            STATE_READ_HEADER = 1
            STATE_READ_CONTENT = 2
            STATE_FINISHED = 3

            FIXED_WARP_ID = 1

            attr :state

            def initialize(pkt_store)
              super(pkt_store, false)
              reset()
            end

            ######################################################
            # Implements Reusable
            ######################################################

            def reset()
              super
              change_state(STATE_FINISHED)
            end


            ######################################################
            # Implements WarpHandler
            ######################################################
            def next_warp_id
              return H1WarpHandler::FIXED_WARP_ID
            end

            def new_warp_data(warp_id)
              return WarpData.new(@ship, warp_id)
            end

            def post_warp_headers(tur)
              twn = tur.town

              twn_path = twn.name
              if !twn_path.end_with?("/")
                twn_path += "/"
              end

              new_uri = @ship.docker.warp_base + tur.req.uri[twn_path.length .. -1]
              cmd = CmdHeader.new_req_header(tur.req.method, new_uri, "HTTP/1.1")

              tur.req.headers.names.each do |name|
                tur.req.headers.values(name).each do |value|
                  cmd.add_header(name, value)
                end
              end

              if tur.req.headers.contains(Headers::X_FORWARDED_FOR)
                cmd.set_header(Headers::X_FORWARDED_FOR, tur.req.headers.get(Headers::X_FORWARDED_FOR))
              else
                cmd.set_header(Headers::X_FORWARDED_FOR, tur.req.remote_address)
              end

              if tur.req.headers.contains(Headers::X_FORWARDED_PROTO)
                cmd.set_header(Headers::X_FORWARDED_PROTO, tur.req.headers.get(Headers::X_FORWARDED_PROTO))
              else
                cmd.set_header(Headers::X_FORWARDED_PROTO, tur.is_secure ? "https" : "http")
              end

              if tur.req.headers.contains(Headers::X_FORWARDED_PORT)
                cmd.set_header(Headers::X_FORWARDED_PORT, tur.req.headers.get(Headers::X_FORWARDED_PORT))
              else
                cmd.set_header(Headers::X_FORWARDED_PORT, tur.req.server_port.to_s)
              end

              if tur.req.headers.contains(Headers::X_FORWARDED_HOST)
                cmd.set_header(Headers::X_FORWARDED_HOST, tur.req.headers.get(Headers::X_FORWARDED_HOST))
              else
                cmd.set_header(Headers::X_FORWARDED_HOST, tur.req.headers.get(Headers::HOST))
              end

              cmd.set_header(Headers::HOST, "#{@ship.docker.host}:#{@ship.docker.port}")
              cmd.set_header(Headers::CONNECTION, "Keep-Alive")

              if BayServer.harbor.trace_header?
                cmd.headers.each do |kv|
                  BayLog.info("%s warp_http reqHdr: %s=%s", tur, kv[0], kv[1])
                end
              end


              @command_packer.post(@ship, cmd)
            end

            def post_warp_contents(tur, buf, start, len, &callback)
              cmd = CmdContent.new(buf, start, len)
              @command_packer.post(@ship, cmd, &callback)
            end

            def post_warp_end(tur)

            end

            def verify_protocol(proto)

            end

            ######################################################
            # Implements H1CommandHandler
            ######################################################

            def handle_header(cmd)
              tur = @ship.get_tour(FIXED_WARP_ID)
              wdat = WarpData.get(tur)
              BayLog.debug("%s handleHeader status=%d", wdat, cmd.status);
              @ship.keeping = false

              if @state == STATE_FINISHED
                change_state(STATE_READ_HEADER)
              end

              if @state != STATE_READ_HEADER
                raise ProtocolException("Header command not expected: state=%d", @state)
              end

              if BayServer.harbor.trace_header?
                BayLog.info("%s warp_http: resStatus: %d", wdat, cmd.status)
              end

              cmd.headers.each do |nv|
                tur.res.headers.add(nv[0], nv[1])
                if BayServer.harbor.trace_header?
                  BayLog.info("%s warp_http: resHeader: %s=%s", wdat, nv[0], nv[1]);
                end
              end

              tur.res.headers.status = cmd.status
              res_cont_len = tur.res.headers.content_length
              tur.res.send_headers(Tour::TOUR_ID_NOCHECK)

              BayLog.debug("%s contLen in header: %d", wdat, res_cont_len)
              if res_cont_len == 0 || cmd.status == HttpStatus::NOT_MODIFIED
                end_res_content(tur)
              else
                change_state(STATE_READ_CONTENT)
                sid = @ship.id()
                tur.res.set_consume_listener do |len, resume|
                  if resume
                    @ship.resume(sid)
                  end
                end
              end
              return NextSocketAction::CONTINUE
            end

            def handle_content(cmd)
              tur = @ship.get_tour(FIXED_WARP_ID)
              wdat = WarpData.get(tur)
              BayLog.debug("%s handleContent len=%d posted%d contLen=%d", wdat, cmd.len, tur.res.bytes_posted, tur.res.bytes_limit);

              if @state != STATE_READ_CONTENT
                raise ProtocolException.new("Content command not expected")
              end

              available = tur.res.send_content(Tour::TOUR_ID_NOCHECK, cmd.buf, cmd.start, cmd.len)
              if tur.res.bytes_posted == tur.res.bytes_limit
                end_res_content(tur)
                return NextSocketAction::CONTINUE
              elsif !available
                return NextSocketAction::SUSPEND
              else
                NextSocketAction::CONTINUE
              end
            end

            def handle_end_content(cmd)
              raise Sink.new()
            end

            def finished()
              return @state == STATE_FINISHED
            end

            def to_s
              return @ship.to_s
            end

            private

            def end_res_content(tur)
              @ship.end_warp_tour(tur)
              tur.res.end_content(Tour::TOUR_ID_NOCHECK)
              reset()
              @ship.keeping = true
            end

            def change_state(new_state)
              @state = new_state
            end
          end
        end
      end
    end
  end
end

