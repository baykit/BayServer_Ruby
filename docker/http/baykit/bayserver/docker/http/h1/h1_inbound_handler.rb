require 'baykit/bayserver/agent/upgrade_exception'

require 'baykit/bayserver/docker/base/inbound_handler'

require 'baykit/bayserver/protocol/package'
require 'baykit/bayserver/tours/req_content_handler'
require 'baykit/bayserver/tours/tour_req'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/util/url_encoder'
require 'baykit/bayserver/util/http_util'
require 'baykit/bayserver/util/headers'

require 'baykit/bayserver/docker/http/h1/h1_command_handler'
require 'baykit/bayserver/docker/http/h1/h1_protocol_handler'
require 'baykit/bayserver/docker/http/h2/package'

module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          class H1InboundHandler < Baykit::BayServer::Docker::Http::H1::H1ProtocolHandler

            class InboundProtocolHandlerFactory
              include Baykit::BayServer::Protocol::ProtocolHandlerFactory  # implements

              def create_protocol_handler(pkt_store)
                return H1InboundHandler.new(pkt_store)
              end
            end

            include Baykit::BayServer::Docker::Base::InboundHandler # implements
            include Baykit::BayServer::Agent
            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Tours
            include Baykit::BayServer::Util
            include Baykit::BayServer::Docker::Http::H2

            STATE_READ_HEADER = 1
            STATE_READ_CONTENT = 2
            STATE_FINISHED = 3

            FIXED_REQ_ID = 1

            attr :header_read
            attr :state
            attr :cur_req_id
            attr :cur_tour
            attr :cur_tour_id
            attr :http_protocol

            def initialize(pkt_store)
              super(pkt_store, true)
              reset()
            end

            ######################################################
            # implements Reusable
            ######################################################
            def reset()
              super
              @cur_req_id = 1
              reset_state()

              @header_read = false
              @http_protocol = nil
              @cur_req_id = 1
              @cur_tour = nil
              @cur_req_id = 0
            end

            ######################################################
            # implements InboundHandler
            ######################################################
            def send_res_headers(tur)

              # determine Connection header value
              if tur.req.headers.get_connection() != Headers::CONNECTION_KEEP_ALIVE
                # If client doesn't support "Keep-Alive", set "Close"
                res_con = "Close"
              else
                res_con = "Keep-Alive"
                # Client supports "Keep-Alive"
                if tur.res.headers.get_connection() != Headers::CONNECTION_KEEP_ALIVE
                  # If tours doesn't need "Keep-Alive"
                  if tur.res.headers.content_length() == -1
                    # If content-length not specified
                    if tur.res.headers.content_type() != nil &&
                      tur.res.headers.content_type().start_with?("text/")
                      # If content is text, connection must be closed
                      res_con = "Close"
                    end
                  end
                end
              end

              tur.res.headers.set(Headers::CONNECTION, res_con)

              if BayServer.harbor.trace_header?
                BayLog.info("%s resStatus:%d", tur, tur.res.headers.status)
                tur.res.headers.names.each do |name|
                  tur.res.headers.values(name).each do |value|
                    BayLog.info("%s resHeader:%s=%s", tur, name, value)
                  end
                end
              end

              cmd = CmdHeader.new_res_header(tur.res.headers, tur.req.protocol)
              @command_packer.post(@ship, cmd)
            end

            def send_res_content(tur, bytes, ofs, len, &callback)
              BayLog.debug("%s H1 send_res_content len=%d", self, len)
              cmd = CmdContent.new(bytes, ofs, len)
              @command_packer.post(@ship, cmd, &callback)
            end

            def send_end_tour(tur, keep_alive, &callback)
              BayLog.trace("%s sendEndTour: tur=%s keep=%s", @ship, tur, keep_alive)

              # Send dummy end request command
              cmd = CmdEndContent.new()

              sid = @ship.ship_id
              ensure_func = lambda do
                if keep_alive && !@ship.postman.zombie?
                  @ship.keeping = true
                  @ship.resume(sid)
                else
                  @command_packer.end(@ship)
                end
              end

              begin
                @command_packer.post(@ship, cmd) do
                  BayLog.debug("%s call back of end content command: tur=%s", @ship, tur)
                  ensure_func.call()
                  callback.call()
                end
              rescue IOError => e
                ensure_func.call()
                raise e
              end
            end

            def send_req_protocol_error(err)
              if @cur_tour == nil
                tur = @ship.get_error_tour()
              else
                tur = @cur_tour
              end

              tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::BAD_REQUEST, err.message, err)
              true
            end

            ######################################################
            # implements H1CommandHandler
            ######################################################
            def handle_header(cmd)
              BayLog.debug("%s handleHeader: method=%s uri=%s proto=", @ship, cmd.method, cmd.uri, cmd.version);

              if @state == STATE_FINISHED
                change_state(STATE_READ_HEADER)
              end

              if @state != STATE_READ_HEADER || @cur_tour != nil
                msg = "Header command not expected: state=#{@state} curTur=#{@cur_tour}"
                BayLog.error(msg)
                self.reset_state();
                raise ProtocolException.new(msg)
              end

              # Check HTTP2
              protocol = cmd.version.upcase
              if protocol == "HTTP/2.0"
                if @ship.port_docker.support_h2
                  @ship.port_docker.return_protocol_handler(@ship.agent, self)
                  new_hnd = ProtocolHandlerStore.get_store(HtpDocker::H2_PROTO_NAME, true, @ship.agent.agent_id).rent()
                  @ship.set_protocol_handler(new_hnd)
                  raise UpgradeException.new()
                else
                  raise ProtocolException.new(
                    BayMessage.get(:HTP_UNSUPPORTED_PROTOCOL, protocol))
                end
              end

              tur = @ship.get_tour(@cur_req_id)
              @cur_tour = tur
              @cur_tour_id = tur.id()
              @cur_req_id += 1

              if tur == nil
                BayLog.error(BayMessage.get(:INT_NO_MORE_TOURS))
                tur = @ship.get_tour(self.cur_req_id, true)
                tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::SERVICE_UNAVAILABLE, "No available tours")
                @ship.agent.shutdown(false)
                return NextSocketAction::CONTINUE
              end

              @ship.keeping = false

              @http_protocol = protocol

              tur.req.uri = URLEncoder.encode_tilde(cmd.uri)
              tur.req.method = cmd.method.upcase
              tur.req.protocol = protocol

              if !(tur.req.protocol == "HTTP/1.1" ||
                   tur.req.protocol == "HTTP/1.0" ||
                   tur.req.protocol == "HTTP/0.9")

                raise ProtocolException.new(BayMessage.get(:HTP_UNSUPPORTED_PROTOCOL, tur.req.protocol))
              end

              cmd.headers.each do |nv|
                tur.req.headers.add(nv[0], nv[1])
              end

              req_cont_len = tur.req.headers.content_length
              BayLog.debug("%s read header method=%s protocol=%s uri=%s contlen=%d",
                           @ship, tur.req.method, tur.req.protocol, tur.req.uri, tur.req.headers.content_length)

              if BayServer.harbor.trace_header?
                cmd.headers.each do |item|
                  BayLog.info("%s h1: reqHeader: %s=%s", tur, item[0], item[1])
                end
              end

              if req_cont_len > 0
                sid = @ship.ship_id
                tur.req.set_consume_listener(req_cont_len) do |len, resume|
                  if resume
                    @ship.resume(sid)
                  end
                end
              end

              begin
                start_tour(tur)

                if req_cont_len <= 0
                  end_req_content(@cur_tour_id, tur)
                  return NextSocketAction::SUSPEND
                else
                  change_state(STATE_READ_CONTENT)
                  return NextSocketAction::CONTINUE
                end
              rescue HttpException => e
                BayLog.debug("%s Http error occurred: %s", self, e)
                if req_cont_len <= 0
                  # no post data
                  tur.res.send_http_exception(Tour::TOUR_ID_NOCHECK, e)

                  reset_state() # next: read empty stdin command
                  return NextSocketAction::CONTINUE
                else
                  # Delay send
                  BayLog.trace("%s error sending is delayed", self)
                  change_state(STATE_READ_CONTENT)
                  tur.error = e
                  tur.req.set_content_handler(ReqContentHandler::DEV_NULL)
                  return NextSocketAction::CONTINUE
                end
              end
            end

            def handle_content(cmd)
              BayLog.debug("%s handleContent: len=%s", @ship, cmd.len)

              if @state != STATE_READ_CONTENT
                s = @state
                reset_state()
                raise ProtocolException.new("Content command not expected: state=#{s}")
              end

              tur = @cur_tour
              tur_id = @cur_tour_id
              success = tur.req.post_content(tur_id, cmd.buf, cmd.start, cmd.len)

              if tur.req.bytes_posted == tur.req.bytes_limit
                if tur.error != nil
                  # Error has occurred on header completed
                  tur.res.send_http_exception(tur_id, tur.error)
                  reset_state()
                  return NextSocketAction::WRITE
                else
                  begin
                    end_req_content(tur_id, tur)
                    return NextSocketAction::CONTINUE
                  rescue HttpException => e
                    tur.res.send_http_exception(tur_id, e)
                    reset_state()
                    return NextSocketAction::WRITE
                  end
                end
              end

              if !success
                return NextSocketAction::SUSPEND
              else
                return NextSocketAction::CONTINUE
              end
            end

            def handle_end_content(cmd)
              raise Sink.new()
            end

            def finished()
              return @state == STATE_FINISHED
            end



            private
            def change_state(new_state)
              @state = new_state
            end

            def reset_state
              @header_read = false
              change_state STATE_FINISHED
              @cur_tour = nil
            end

            def end_req_content(chk_tur_id, tur)
              tur.req.end_content(chk_tur_id)
              reset_state()
            end

            def start_tour(tur)
              secure = @ship.port_docker.secure
              HttpUtil.parse_host_port(tur, secure ? 443 : 80)
              HttpUtil.parse_authorization(tur)

              skt = @ship.socket

              client_adr = tur.req.headers.get(Headers::X_FORWARDED_FOR)
              if client_adr
                tur.req.remote_address = client_adr
                tur.req.remote_port = nil
              else
                begin
                  remote_addr = skt.getpeername()
                  tur.req.remote_port, tur.req.remote_address = Socket.unpack_sockaddr_in(remote_addr)
                rescue => e
                  BayLog.error_e(e, "%s Cannot get remote address (Ignore): %s", tur, e)
                end
              end

              tur.req.remote_host_func = lambda do
                HttpUtil.resolve_remote_host(tur.req.remote_address)
              end

              server_addr = skt.getsockname
              server_port, tur.req.server_address = Socket.unpack_sockaddr_in(server_addr)

              tur.req.server_port = tur.req.req_port
              tur.req.server_name = tur.req.req_host
              tur.is_secure = secure

              tur.go()
            end

          end
        end
      end
    end
  end
end
