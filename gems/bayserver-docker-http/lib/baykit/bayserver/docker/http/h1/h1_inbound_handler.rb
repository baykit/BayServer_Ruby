# frozen_string_literal: true

require 'openssl'
require 'baykit/bayserver/agent/upgrade_exception'

require 'baykit/bayserver/common/inbound_handler'

require 'baykit/bayserver/protocol/package'
require 'baykit/bayserver/tours/req_content_handler'
require 'baykit/bayserver/tours/tour_req'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/util/url_encoder'
require 'baykit/bayserver/util/http_util'
require 'baykit/bayserver/util/io_util'
require 'baykit/bayserver/util/headers'

require 'baykit/bayserver/protocol/packet_packer'
require 'baykit/bayserver/protocol/command_packer'

require 'baykit/bayserver/docker/http/h1/h1_handler'
require 'baykit/bayserver/docker/http/h1/h1_command_handler'
require 'baykit/bayserver/docker/http/h1/h1_command_unpacker'
require 'baykit/bayserver/docker/http/h1/h1_packet_unpacker'
require 'baykit/bayserver/docker/http/h1/h1_protocol_handler'
require 'baykit/bayserver/docker/http/h2/package'

module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          class H1InboundHandler

            class InboundProtocolHandlerFactory
              include Baykit::BayServer::Protocol::ProtocolHandlerFactory  # implements

              include Baykit::BayServer::Protocol

              def create_protocol_handler(pkt_store)
                ib_handler = H1InboundHandler.new
                cmd_unpacker = H1CommandUnPacker.new(ib_handler, true)
                pkt_unpacker = H1PacketUnPacker.new(cmd_unpacker, pkt_store)
                pkt_packer = PacketPacker.new
                cmd_packer = CommandPacker.new(pkt_packer, pkt_store)

                proto_handler = H1ProtocolHandler.new(ib_handler, pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, true)
                ib_handler.init(proto_handler)
                return proto_handler
              end
            end

            include Baykit::BayServer::Common::InboundHandler # implements
            include H1Handler # implements

            include Baykit::BayServer::Agent
            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Tours
            include Baykit::BayServer::Util
            include Baykit::BayServer::Docker::Http::H1::Command
            include Baykit::BayServer::Docker::Http::H2
            include OpenSSL

            STATE_READ_HEADER = 1
            STATE_READ_CONTENT = 2
            STATE_FINISHED = 3

            FIXED_REQ_ID = 1

            # Canonical (uppercase) HTTP version / method strings. Hash
            # lookup returns the frozen canonical string when the input
            # already matches one of the well-known values; the upcase
            # fallback only fires for case-irregular input. Avoids the
            # per-request allocation `cmd.version.upcase` /
            # `cmd.method.upcase` would otherwise produce.
            HTTP_VERSION_CANON = {
              "HTTP/1.1" => "HTTP/1.1".freeze,
              "HTTP/1.0" => "HTTP/1.0".freeze,
              "HTTP/0.9" => "HTTP/0.9".freeze,
              "HTTP/2.0" => "HTTP/2.0".freeze,
            }.freeze
            HTTP_METHOD_CANON = %w[GET POST PUT DELETE HEAD OPTIONS PATCH CONNECT TRACE].each_with_object({}) do |m, h|
              h[m] = m.dup.freeze
            end.freeze

            # Pre-frozen byte strings used by the chunked-encoding output
            # path. LAST_CHUNK is the HTTP/1.1 terminator (`0\r\n\r\n`).
            CRLF = "\r\n".b.freeze
            LAST_CHUNK = "0\r\n\r\n".b.freeze

            attr :protocol_handler
            attr :header_read
            attr :state
            attr :cur_req_id
            attr :cur_tour
            attr :cur_tour_id
            attr :http_protocol

            # Whether the response in flight is being framed as HTTP/1.1
            # "Transfer-Encoding: chunked". Set in send_res_headers when the
            # upstream (or local handler) didn't supply a Content-Length
            # and the client speaks HTTP/1.1, so we can keep the connection
            # alive without a known body length. Each subsequent
            # send_res_content / send_end_tour call inspects this to decide
            # whether to wrap bytes in chunked frames.
            attr_accessor :chunked_response

            def initialize
              super
              reset
            end

            def init(proto_handler)
              @protocol_handler = proto_handler
            end

            ######################################################
            # implements Reusable
            ######################################################
            def reset()
              reset_state()

              @header_read = false
              @http_protocol = nil
              @cur_req_id = 1
              @cur_tour = nil
              # Clear per-connection address cache so the next time
              # this handler is rented out from the pool it does not
              # return the previous client's IP.
              @remote_addr = nil
              @server_addr = nil
              @cur_req_id = 0
              @chunked_response = false
            end

            ######################################################
            # implements InboundHandler
            ######################################################
            def send_res_headers(tur)
              @chunked_response = false

              # determine Connection header value
              if tur.req.headers.get_connection() != Headers::CONNECTION_KEEP_ALIVE && tur.req.headers.get_connection() != Headers::CONNECTION_UNKNOWN
                # If client doesn't support "Keep-Alive", set "Close"
                res_con = "Close"
              elsif tur.res.headers.status != HttpStatus::OK
                res_con = "Close"
              else
                # Client supports "Keep-Alive"
                res_con = "Keep-Alive"

                # If Content-Length is not set and the response has a body, we
                # need a way to delimit the response. HTTP/1.1 supports
                # chunked transfer-encoding for this exact case; falling back
                # to "Connection: Close" (= read until EOF) was the historical
                # BayServer behaviour but kills keep-alive against any backend
                # that doesn't pre-compute Content-Length (e.g. php-fpm).
                #
                # For HTTP/1.1 + missing Content-Length + already-set
                # Transfer-Encoding == none, set chunked. HTTP/1.0 / 0.9 don't
                # support chunked, so they still close.
                if tur.res.headers.content_length() == -1
                  existing_te = tur.res.headers.get(Headers::HDR_TRANSFER_ENCODING)
                  upstream_already_chunked =
                    existing_te != nil && existing_te.downcase.include?("chunked")

                  if tur.req.protocol == "HTTP/1.1"
                    if !upstream_already_chunked
                      tur.res.headers.set(Headers::HDR_TRANSFER_ENCODING, "chunked")
                    end
                    @chunked_response = true
                  else
                    # HTTP/1.0 has no chunked: connection-close framing.
                    res_con = "Close"
                  end
                end
              end

              tur.res.headers.set(Headers::CONNECTION, res_con)

              if BayServer.harbor.trace_header
                BayLog.info("%s resStatus:%d", tur, tur.res.headers.status)
                tur.res.headers.names.each do |name|
                  tur.res.headers.values(name).each do |value|
                    BayLog.info("%s resHeader:%s=%s", tur, name, value)
                  end
                end
              end

              cmd = CmdHeader.new_res_header(tur.res.headers, tur.req.protocol)
              @protocol_handler.post(cmd, false)
            end

            def send_res_content(tur, bytes, ofs, len, &callback)
              BayLog.debug("%s H1 send_res_content len=%d", self, len)
              if @chunked_response && len > 0
                # Wrap in chunked transfer-encoding frame:
                #   <hex-len>\r\n<data>\r\n
                hex = len.to_s(16)
                buf = String.new(capacity: hex.bytesize + 2 + len + 2, encoding: Encoding::ASCII_8BIT)
                buf << hex << CRLF
                buf << bytes.byteslice(ofs, len)
                buf << CRLF
                cmd = CmdContent.new(buf, 0, buf.bytesize)
                return @protocol_handler.post(cmd, false, &callback)
              end
              cmd = CmdContent.new(bytes, ofs, len)
              return @protocol_handler.post(cmd, false, &callback)
            end

            def transfer_content(tur, file_rd, ofs, len, &lis)
              ship.transporter.req_transfer(tur.ship.rudder, file_rd, ofs, len, &lis)
            end

            def send_end_tour(tur, &callback)
              keep_alive = tur.res.headers.get_connection() == Headers::CONNECTION_KEEP_ALIVE
              BayLog.trace("%s sendEndTour: tur=%s keep=%s", ship, tur, keep_alive)

              # Close out the chunked stream with the last-chunk + final CRLF.
              # post() is fire-and-forget here -- the actual end signal is the
              # CmdEndContent below, which carries the keepalive callback.
              if @chunked_response
                begin
                  @protocol_handler.post(
                    CmdContent.new(LAST_CHUNK, 0, LAST_CHUNK.bytesize), false)
                rescue IOError => e
                  BayLog.debug_e(e, "%s post(last-chunk) failed", ship)
                  raise e
                end
                @chunked_response = false
              end

              # Send dummy end request command
              cmd = CmdEndContent.new()

              sid = ship.ship_id
              ensure_func = lambda do
                if keep_alive
                  ship.keeping = true
                  ship.resume_read(sid)
                else
                  ship.post_close
                end
              end

              begin
                @protocol_handler.post(cmd, true) do
                  BayLog.debug("%s call back of end content command: tur=%s", ship, tur)
                  ensure_func.call()
                  callback.call()
                end
              rescue IOError => e
                ensure_func.call()
                raise e
              end
            end

            def on_protocol_error(err)
              if @cur_tour == nil
                tur = ship.get_error_tour()
              else
                tur = @cur_tour
              end

              tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::BAD_REQUEST, err.message, err)
              false
            end

            ######################################################
            # implements H1CommandHandler
            ######################################################
            def handle_header(cmd)
              BayLog.debug("%s handleHeader: method=%s uri=%s proto=", ship, cmd.method, cmd.uri, cmd.version);
              sip = ship

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
              protocol = HTTP_VERSION_CANON[cmd.version] || cmd.version.upcase
              if protocol == "HTTP/2.0"
                if ship.port_docker.support_h2
                  ship.port_docker.return_protocol_handler(ship.agent_id, @protocol_handler)
                  new_hnd = ProtocolHandlerStore.get_store(HtpDocker::H2_PROTO_NAME, true, sip.agent_id).rent()
                  sip.set_protocol_handler(new_hnd)
                  raise UpgradeException.new()
                else
                  raise ProtocolException.new(
                    BayMessage.get(:HTP_UNSUPPORTED_PROTOCOL, protocol))
                end
              end

              tur = sip.get_tour(@cur_req_id)

              if tur == nil
                BayLog.error(BayMessage.get(:INT_NO_MORE_TOURS))
                tur = sip.get_tour(self.cur_req_id, true)
                tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::SERVICE_UNAVAILABLE, "No available tours")
                return NextSocketAction::CONTINUE
              end

              @cur_tour = tur
              @cur_tour_id = tur.id()
              @cur_req_id += 1

              ship.keeping = false

              @http_protocol = protocol

              tur.req.uri = URLEncoder.encode_tilde(cmd.uri)
              tur.req.method = HTTP_METHOD_CANON[cmd.method] || cmd.method.upcase
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
                           ship, tur.req.method, tur.req.protocol, tur.req.uri, tur.req.headers.content_length)

              if BayServer.harbor.trace_header
                cmd.headers.each do |item|
                  BayLog.info("%s h1: reqHeader: %s=%s", tur, item[0], item[1])
                end
              end

              if req_cont_len > 0
                tur.req.set_limit(req_cont_len)
              end

              begin
                start_tour(tur)

                if req_cont_len <= 0
                  end_req_content(@cur_tour_id, tur)
                  return NextSocketAction::SUSPEND  # end reading
                else
                  change_state(STATE_READ_CONTENT)
                  return NextSocketAction::CONTINUE
                end
              rescue HttpException => e
                BayLog.debug_e(e, "%s Http error occurred: %s", self, e)
                if req_cont_len <= 0
                  # no post data
                  tur.req.abort
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
              BayLog.debug("%s handleContent: len=%s", ship, cmd.len)

              if @state != STATE_READ_CONTENT
                s = @state
                reset_state()
                raise ProtocolException.new("Content command not expected: state=#{s}")
              end

              tur = @cur_tour
              tur_id = @cur_tour_id
              begin
                sid = ship.ship_id
                success = tur.req.post_req_content(tur_id, cmd.buf, cmd.start, cmd.len) do |len, resume|
                  if resume
                    tur.ship.resume_read(sid)
                  end
                end

                if tur.req.bytes_posted == tur.req.bytes_limit
                  if tur.error != nil
                    # Error has occurred on header completed
                    #tur.res.send_http_exception(tur_id, tur.error)
                    #reset_state()
                    #return NextSocketAction::WRITE
                    BayLog.debug("%s Delay report error", tur)
                    raise tur.error
                  else
                    end_req_content(tur_id, tur)
                    return NextSocketAction::CONTINUE
                  end
                end

                if !success
                  return NextSocketAction::SUSPEND  # end reading
                else
                  return NextSocketAction::CONTINUE
                end

              rescue HttpException => e
                tur.res.send_http_exception(tur_id, e)
                reset_state()
                return NextSocketAction::WRITE
              end
            end

            def handle_end_content(cmd)
              raise Sink.new()
            end

            def req_finished()
              return @state == STATE_FINISHED
            end

            private
            def ship
              return @protocol_handler.ship
            end

            def change_state(new_state)
              @state = new_state
            end

            def reset_state
              @header_read = false
              change_state STATE_FINISHED
              @cur_tour = nil
            end

            def end_req_content(chk_tur_id, tur)
              tur.req.end_req_content(chk_tur_id)
              reset_state()
            end

            def start_tour(tur)
              secure = ship.port_docker.secure
              HttpUtil.parse_host_port(tur, secure ? 443 : 80)
              HttpUtil.parse_authorization(tur)

              client_adr = tur.req.headers.get(Headers::X_FORWARDED_FOR)
              if client_adr
                tur.req.remote_address = client_adr
                tur.req.remote_port = nil
              else
                # H1InboundHandler is per-connection so an instance
                # ivar memoizes for the life of the connection. The
                # IOUtil helper skips Socket.unpack_sockaddr_in (the
                # single hottest non-syscall frame at ~16% on 128B
                # HTTP plain profiling).
                begin
                  @remote_addr ||= IOUtil.get_remote_address(ship.rudder.io)
                  tur.req.remote_address, tur.req.remote_port = @remote_addr
                rescue => e
                  BayLog.error_e(e, "%s Cannot get remote address (Ignore): %s", tur, e)
                end
              end

              tur.req.remote_host_func = lambda do
                HttpUtil.resolve_remote_host(tur.req.remote_address)
              end

              begin
                @server_addr ||= IOUtil.get_server_address(ship.rudder.io)
                tur.req.server_address = @server_addr
              rescue => e
                BayLog.error_e(e, "%s Cannot get server address (Ignore): %s", tur, e)
              end

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
