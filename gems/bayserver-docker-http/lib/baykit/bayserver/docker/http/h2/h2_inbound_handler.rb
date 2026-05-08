require 'baykit/bayserver/common/inbound_handler'

require 'baykit/bayserver/protocol/packet_packer'
require 'baykit/bayserver/protocol/command_packer'

require 'baykit/bayserver/docker/http/h2/package'
require 'baykit/bayserver/docker/http/h2/h2_protocol_handler'
require 'baykit/bayserver/docker/http/h2/h2_handler'
require 'baykit/bayserver/docker/http/h2/command/package'
require 'baykit/bayserver/protocol/package'
require 'baykit/bayserver/tours/req_content_handler'
require 'baykit/bayserver/tours/tour_req'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/util/url_encoder'
require 'baykit/bayserver/util/http_util'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2InboundHandler

            class InboundProtocolHandlerFactory
              include Baykit::BayServer::Protocol::ProtocolHandlerFactory  # implements

              include Baykit::BayServer::Protocol

              def create_protocol_handler(pkt_store)

                ib_handler = H2InboundHandler.new
                cmd_unpacker = H2CommandUnPacker.new(ib_handler)
                pkt_unpacker = H2PacketUnPacker.new(cmd_unpacker, pkt_store, true)
                pkt_packer = PacketPacker.new()
                cmd_packer = CommandPacker.new(pkt_packer, pkt_store)

                proto_handler = H2ProtocolHandler.new(ib_handler, pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, true)
                ib_handler.init(proto_handler)
                return proto_handler
              end
            end

            include Baykit::BayServer::Common::InboundHandler  # implements
            include H2Handler # implements

            include Baykit::BayServer::Agent
            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Tours
            include Baykit::BayServer::Util
            include Baykit::BayServer::Docker::Http::H2::Command

            # RFC 7540 § 6.9.1: the flow-control window must not exceed 2^31-1.
            # We track (but do not yet enforce on send) the outbound window so that
            # WINDOW_UPDATE frames that would overflow it can be rejected per spec.
            MAX_WINDOW = 0x7FFFFFFF
            DEFAULT_INITIAL_WINDOW = 65535

            attr :protocol_handler
            attr :req_cont_len
            attr :req_cont_read
            attr :header_read
            attr :window_size
            attr :settings
            attr :analyzer
            attr :http_protocol
            attr :req_header_tbl
            attr :res_header_tbl
            attr :header_buffer

            def initialize
              @window_size = BayServer.harbor.ship_buffer_size
              @settings = H2Settings.new
              @analyzer = HeaderBlockAnalyzer.new
              @req_header_tbl = HeaderTable.create_dynamic_table()
              @res_header_tbl = HeaderTable.create_dynamic_table()
              @header_buffer = SimpleBuffer.new
              @conn_send_window = DEFAULT_INITIAL_WINDOW
              @stream_send_windows = {}
            end

            ######################################################
            # implements Reusable
            ######################################################

            def reset()
              @header_read = false
              @req_cont_len = 0
              @req_cont_read = 0
              @header_buffer.reset

              # Flow-control tracking is per-connection; pooled handlers must start
              # each new connection with fresh windows.
              @conn_send_window = DEFAULT_INITIAL_WINDOW
              @stream_send_windows.clear
            end

            def init(proto_handler)
              @protocol_handler = proto_handler
            end

            ######################################################
            # implements InboundHandler
            ######################################################

            def send_res_headers(tur)
              bld = HeaderBlockBuilder.new()

              header_blocks = []

              blk = bld.build_header_block(":status", tur.res.headers.status.to_s, @res_header_tbl)
              header_blocks << blk

              # headers
              if BayServer.harbor.trace_header
                BayLog.info("%s res status: %d", tur, tur.res.headers.status)
              end
              tur.res.headers.names.each do |name|
                if name.casecmp?("connection")
                  BayLog.trace("%s Connection header is discarded", tur)
                else
                  tur.res.headers.values(name).each do |value|
                    if BayServer.harbor.trace_header
                      BayLog.info("%s H2 res header: %s=%s", tur, name, value)
                    end
                    blk = bld.build_header_block(name, value, @res_header_tbl)
                    header_blocks.append(blk)
                  end
                end
              end

              buf = SimpleBuffer.new
              HeaderBlockRenderer.new(buf).render_header_blocks(header_blocks)

              pos = 0
              len = buf.length
              while len > 0
                chunk_len = [len, H2Packet::DEFAULT_PAYLOAD_MAXLEN].min

                if pos == 0
                  hcmd = CmdHeaders.new(tur.req.key)
                  hcmd.excluded = false
                  hcmd.data = buf.bytes
                  hcmd.start = pos
                  hcmd.length = len
                  cmd = hcmd

                else
                  ccmd = CmdContinuation.new(tur.req.key)
                  ccmd.data = buf.bytes
                  ccmd.start = pos
                  ccmd.length = len
                  cmd = ccmd

                end

                cmd.flags.set_padded(false)

                pos += chunk_len
                len -= chunk_len
                if len == 0
                    cmd.flags.set_end_headers(true)
                end

                @protocol_handler.post(cmd, false)
              end
            end

            def send_res_content(tur, bytes, ofs, len, &callback)
              BayLog.debug("%s send_res_content len=%d", self, len)
              # Account for the bytes we are about to send against the flow-control
              # windows. Without this, handle_window_update only ever sees
              # WINDOW_UPDATE additions and eventually trips the > 2^31-1 guard
              # on long-lived high-throughput connections.
              if len > 0
                stream_id = tur.req.key
                @conn_send_window -= len
                str_win = (@stream_send_windows[stream_id] || DEFAULT_INITIAL_WINDOW) - len
                @stream_send_windows[stream_id] = str_win
              end
              cmd = CmdData.new(tur.req.key, nil, bytes, ofs, len);
              return @protocol_handler.post(cmd, false, &callback)
            end

            def transfer_content(tur, file_rd, ofs, len, &lis)
              raise Sink.new
            end

            def send_end_tour(tur, &callback)
              BayLog.debug("%s send_end_tour. tur=%s", self, tur)
              cmd = CmdData.new(tur.req.key, nil, [], 0, 0)
              cmd.flags.set_end_stream(true)
              @protocol_handler.post(cmd, true, &callback)
              # NOTE: We intentionally do NOT mark the stream CLOSED in the
              # command unpacker here. See the Java commit notes for why.
            end

            def on_protocol_error(err)
              BayLog.error_e err
              cmd = CmdGoAway.new(H2ProtocolHandler::CTL_STREAM_ID)
              cmd.stream_id = H2ProtocolHandler::CTL_STREAM_ID
              cmd.last_stream_id = H2ProtocolHandler::CTL_STREAM_ID
              # H2ProtocolException carries a caller-specified error code;
              # bare ProtocolException defaults to PROTOCOL_ERROR per RFC 7540 § 5.4.
              if err.respond_to?(:error_code)
                cmd.error_code = err.error_code
              else
                cmd.error_code = H2ErrorCode::PROTOCOL_ERROR
              end
              cmd.debug_data = "Thank you!"
              begin
                # Defer the close until the GOAWAY frame has actually been written.
                @protocol_handler.post(cmd, true) do |avail|
                  @protocol_handler.ship.post_close()
                end
              rescue IOError => e
                BayLog.error_e(e)
              end
              return false
            end


            ######################################################
            # implements H2CommandHandler
            ######################################################

            def handle_preface(cmd)
              BayLog.debug("%s h2: handle_preface: proto=%s", ship, cmd.protocol)

              @http_protocol = cmd.protocol

              set = CmdSettings.new(H2ProtocolHandler::CTL_STREAM_ID)
              set.stream_id = 0
              set.items.append(CmdSettings::Item.new(CmdSettings::MAX_CONCURRENT_STREAMS, BayServer.harbor.max_tours_per_ship))
              set.items.append(CmdSettings::Item.new(CmdSettings::INITIAL_WINDOW_SIZE, @window_size))
              @protocol_handler.post(set, true)

              set = CmdSettings.new(H2ProtocolHandler::CTL_STREAM_ID)
              set.stream_id = 0
              set.flags.set_ack(true)

              return NextSocketAction::CONTINUE
            end


            def handle_headers(cmd)
              BayLog.debug("%s handle_headers: stm=%d dep=%d weight=%d", ship, cmd.stream_id, cmd.stream_dependency, cmd.weight)

              tur = get_tour(cmd.stream_id)
              if tur == nil
                BayLog.error(BayMessage.get(:INT_NO_MORE_TOURS))
                tur = ship.get_tour(cmd.stream_id, true)
                tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::SERVICE_UNAVAILABLE, "No available tours")
                return NextSocketAction::CONTINUE
              end
              if !tur.preparing?
                raise ProtocolException.new("%s Tour is not preparing.", tur)
              end

              if cmd.flags.end_headers?
                return on_end_header(tur, cmd.data, cmd.start, cmd.length)
              else
                @header_buffer.put(cmd.data, cmd.start, cmd.length)
              end

              NextSocketAction::CONTINUE
            end

            def handle_data(cmd)
              BayLog.debug("%s handle_data: stm=%d len=%d", ship, cmd.stream_id, cmd.length)

              tur = get_tour(cmd.stream_id)
              if tur == nil
                raise RuntimeError.new("Invalid stream id: #{cmd.stream_id}")
              end
              if !tur.reading?
                raise ProtocolException.new("%s Tour is not reading.", tur)
              end

              # RFC 7540 § 8.1.2.6: if content-length is given, the sum of DATA
              # payload lengths MUST match it. Check on the END_STREAM boundary.
              if cmd.flags.end_stream?
                cont_len = tur.req.headers.content_length
                if cont_len >= 0 && tur.req.bytes_posted + cmd.length != cont_len
                  raise ProtocolException.new(
                    "content-length #{cont_len} does not match DATA payload #{tur.req.bytes_posted + cmd.length}")
                end
              end

              begin
                success = false
                if cmd.length > 0
                  tid = tur.tour_id

                  success = tur.req.post_req_content(Tour::TOUR_ID_NOCHECK, cmd.data, cmd.start, cmd.length) do |len, resume|
                    tur.check_tour_id(tid)
                    if len > 0
                      upd = CmdWindowUpdate.new(cmd.stream_id)
                      upd.window_size_increment = len
                      upd2 = CmdWindowUpdate.new( 0)
                      upd2.window_size_increment = len
                      begin
                        @protocol_handler.post(upd, false)
                        @protocol_handler.post(upd2, true)
                      rescue IOError => e
                        BayLog.error_e(e)
                      end
                    end

                    if resume
                      tur.ship.resume_read(Ship::SHIP_ID_NOCHECK)
                    end
                  end

                  if tur.req.bytes_posted >= tur.req.headers.content_length
                    if tur.error != nil
                      # Error has occurred on header completed
                      BayLog.debug("%s Delay report error", tur)
                      raise tur.error
                    else
                      end_req_content(tur.id(), tur)
                    end
                  end
                end

                if !success
                  return NextSocketAction::SUSPEND
                else
                  return NextSocketAction::CONTINUE
                end

              rescue HttpException => e
                tur.req.abort
                tur.res.send_http_exception(Tour::TOUR_ID_NOCHECK, e)
                return NextSocketAction::CONTINUE
              end

            end

            def handle_priority(cmd)
              if cmd.stream_id == 0
                raise ProtocolException.new("Invalid stream id")
              end

              BayLog.debug("%s handlePriority: stmid=%d dep=%d, wgt=%d",
                           ship, cmd.stream_id, cmd.stream_dependency, cmd.weight);

              return NextSocketAction::CONTINUE
            end

            def handle_settings(cmd)
              BayLog.debug("%s handleSettings: stmid=%d", ship, cmd.stream_id);

              if cmd.flags.ack?
                return NextSocketAction::CONTINUE
              end

              cmd.items.each do |item|
                BayLog.debug("%s handle: Setting id=%d, value=%d", ship, item.id, item.value);
                case item.id
                when CmdSettings::HEADER_TABLE_SIZE
                  @settings.header_table_size = item.value

                when CmdSettings::ENABLE_PUSH
                  # RFC 7540 § 6.5.2: ENABLE_PUSH must be 0 or 1.
                  if item.value != 0 && item.value != 1
                    raise ProtocolException.new("SETTINGS_ENABLE_PUSH must be 0 or 1, got #{item.value}")
                  end
                  @settings.enable_push = (item.value != 0)

                when CmdSettings::MAX_CONCURRENT_STREAMS
                  @settings.max_concurrent_streams = item.value

                when CmdSettings::INITIAL_WINDOW_SIZE
                  # RFC 7540 § 6.5.2: INITIAL_WINDOW_SIZE must not exceed 2^31-1;
                  # larger values are FLOW_CONTROL_ERROR.
                  if item.value < 0
                    raise H2ProtocolException.new(H2ErrorCode::FLOW_CONTROL_ERROR,
                      "SETTINGS_INITIAL_WINDOW_SIZE exceeds 2^31-1: #{item.value}")
                  end
                  @settings.initial_window_size = item.value

                when CmdSettings::MAX_FRAME_SIZE
                  # RFC 7540 § 6.5.2: MAX_FRAME_SIZE must be within [2^14, 2^24-1].
                  if item.value < H2Packet::DEFAULT_PAYLOAD_MAXLEN || item.value > H2Packet::MAX_PAYLOAD_LEN
                    raise ProtocolException.new("SETTINGS_MAX_FRAME_SIZE out of range: #{item.value}")
                  end
                  @settings.max_frame_size = item.value

                when CmdSettings::MAX_HEADER_LIST_SIZE
                  @settings.max_header_list_size = item.value

                else
                  BayLog.debug("Invalid settings id (Ignore): %d", item.id)

                end
              end

              res = CmdSettings.new(0, H2Flags.new(H2Flags::FLAGS_ACK))
              @protocol_handler.post(res, true)
              return NextSocketAction::CONTINUE
            end

            def handle_window_update(cmd)
              if cmd.window_size_increment == 0
                raise ProtocolException.new("Invalid increment value")
              end
              BayLog.debug("%s handleWindowUpdate: stmid=%d siz=%d", ship,  cmd.stream_id, cmd.window_size_increment);

              # RFC 7540 § 6.9.1: adding the increment must not push the window
              # above 2^31-1. Overflow at the connection level is a connection
              # error FLOW_CONTROL_ERROR (GOAWAY); at the stream level it is a
              # stream error (RST_STREAM).
              if cmd.stream_id == 0
                @conn_send_window += (cmd.window_size_increment & 0xFFFFFFFF)
                if @conn_send_window > MAX_WINDOW
                  raise H2ProtocolException.new(H2ErrorCode::FLOW_CONTROL_ERROR,
                    "Connection send window overflow: #{@conn_send_window}")
                end
              else
                win = (@stream_send_windows[cmd.stream_id] || DEFAULT_INITIAL_WINDOW) +
                      (cmd.window_size_increment & 0xFFFFFFFF)
                if win > MAX_WINDOW
                  rst = CmdRstStream.new(cmd.stream_id)
                  rst.error_code = H2ErrorCode::FLOW_CONTROL_ERROR
                  @protocol_handler.post(rst, true)
                  @stream_send_windows.delete(cmd.stream_id)
                  return NextSocketAction::CONTINUE
                end
                @stream_send_windows[cmd.stream_id] = win
              end
              return NextSocketAction::CONTINUE
            end

            def handle_go_away(cmd)
              BayLog.debug("%s received GoAway: lastStm=%d code=%d desc=%s debug=%s",
                           ship, cmd.last_stream_id, cmd.error_code, H2ErrorCode.msg.get(cmd.error_code.to_s.to_sym), cmd.debug_data);
              return NextSocketAction::CLOSE
            end

            def handle_ping(cmd)
              BayLog.debug("%s handle_ping: stm=%d ack=%s", ship, cmd.stream_id, cmd.flags.ack?)

              # RFC 7540 § 6.7: a PING frame with the ACK flag is a response to a
              # PING the endpoint sent; we never send PINGs, and in any case an
              # endpoint MUST NOT respond to PING with ACK set.
              if cmd.flags.ack?
                return NextSocketAction::CONTINUE
              end

              res = CmdPing.new(cmd.stream_id, H2Flags.new(H2Flags::FLAGS_ACK), cmd.opaque_data)
              @protocol_handler.post(res, true)
              return NextSocketAction::CONTINUE
            end

            def handle_rst_stream(cmd)
              BayLog.warn("%s received RstStream: stmid=%d code=%d desc=%s",
                           ship, cmd.stream_id, cmd.error_code, H2ErrorCode.msg.get(cmd.error_code.to_s.to_sym))
              return NextSocketAction::CONTINUE
            end

            def handle_continuation(cmd)
              BayLog.debug("%s handle_continuation: stm=%d", ship, cmd.stream_id)
              tur = get_tour(cmd.stream_id)
              if tur == nil
                raise ArgumentError("Invalid stream id: " + cmd.stream_id)
              end

              @header_buffer.put(cmd.data, cmd.start, cmd.length)
              if cmd.flags.end_headers?
                return on_end_header(tur, @header_buffer.bytes, 0, @header_buffer.length)
              end

              return NextSocketAction::CONTINUE
            end

            private

            def ship
              return @protocol_handler.ship
            end

            def get_tour(key)
              ship.get_tour(key)
            end

            def end_req_content(check_id, tur)
              tur.req.end_req_content check_id
            end

            def start_tour(tur)
              HttpUtil.parse_host_port(tur, ship.port_docker.secure ? 443 : 80)
              HttpUtil.parse_authorization(tur)

              tur.req.protocol = @http_protocol

              skt = ship.rudder.io
              if skt.kind_of? OpenSSL::SSL::SSLSocket
                skt = skt.io
              end

              client_adr = tur.req.headers.get(Headers::X_FORWARDED_FOR)
              if client_adr
                tur.req.remote_address = client_adr
                tur.req.remote_port = nil
              else
                begin
                  remote_addr = skt.getpeername()
                rescue SystemCallError => e
                  BayLog.debug_e(e)
                  remote_addr = nil
                end
                if remote_addr
                  tur.req.remote_port, tur.req.remote_address = Socket.unpack_sockaddr_in(remote_addr)
                end
              end

              tur.req.remote_host_func = lambda {  HttpUtil.resolve_remote_host(tur.req.remote_address) }




              begin
                server_addr = skt.getsockname
                server_port, tur.req.server_address = Socket.unpack_sockaddr_in(server_addr)
              rescue => e
                BayLog.error_e(e)
                BayLog.debug("%s Caught error (Continue)", ship)
              end

              tur.req.server_port = tur.req.req_port
              tur.req.server_name = tur.req.req_host
              tur.is_secure = ship.port_docker.secure

              tur.go
            end

            def has_upper_case(s)
              return false if s == nil
              s.each_char { |c| return true if c >= 'A' && c <= 'Z' }
              false
            end

            def on_end_header(tur, buf, start, len)

              begin
                header_blocks = HeaderBlockParser.new(buf, start, len).parse_header_blocks()
              rescue RuntimeError => e
                # Truncated/corrupt HPACK input surfaces as various errors.
                # Convert those to a protocol-level COMPRESSION_ERROR per RFC 7541 § 2.3.3.
                raise ProtocolException.new("HPACK decode failed: #{e.message}")
              end

              # Pseudo-header + header-field validation (RFC 7540 § 8.1.2).
              saw_method = false
              saw_scheme = false
              saw_path = false
              saw_authority = false
              saw_regular_header = false

              header_blocks.each do |blk|
                if blk.op == HeaderBlock::UPDATE_DYNAMIC_TABLE_SIZE
                  BayLog.trace("%s header block update table size: %d", tur, blk.size)
                  @req_header_tbl.set_size(blk.size)
                  next
                end
                @analyzer.analyze_header_block(blk, @req_header_tbl)
                if BayServer.harbor.trace_header
                  BayLog.info("%s req header: %s=%s :%s", tur, @analyzer.name, @analyzer.value, blk);
                end

                if @analyzer.name == nil
                  next
                end

                # § 8.1.2: header field names must be lowercase.
                if has_upper_case(@analyzer.raw_name)
                  raise ProtocolException.new("Header name must be lowercase: #{@analyzer.raw_name}")
                end

                if @analyzer.pseudo
                  # § 8.1.2.1: pseudo-header fields must precede regular headers.
                  if saw_regular_header
                    raise ProtocolException.new("Pseudo-header #{@analyzer.raw_name} appears after a regular header")
                  end

                  case @analyzer.raw_name
                  when HeaderTable::PSEUDO_HEADER_METHOD
                    raise ProtocolException.new("Duplicated :method") if saw_method
                    saw_method = true
                    tur.req.method = @analyzer.method

                  when HeaderTable::PSEUDO_HEADER_SCHEME
                    raise ProtocolException.new("Duplicated :scheme") if saw_scheme
                    saw_scheme = true

                  when HeaderTable::PSEUDO_HEADER_PATH
                    raise ProtocolException.new("Duplicated :path") if saw_path
                    if @analyzer.path == nil || @analyzer.path.empty?
                      raise ProtocolException.new("Empty :path pseudo-header")
                    end
                    saw_path = true
                    tur.req.uri = @analyzer.path

                  when HeaderTable::PSEUDO_HEADER_AUTHORITY
                    raise ProtocolException.new("Duplicated :authority") if saw_authority
                    saw_authority = true
                    tur.req.headers.add(@analyzer.name, @analyzer.value)

                  when HeaderTable::PSEUDO_HEADER_STATUS
                    raise ProtocolException.new(":status pseudo-header is invalid in a request")

                  else
                    raise ProtocolException.new("Unknown pseudo-header: #{@analyzer.raw_name}")
                  end

                else
                  saw_regular_header = true
                  # § 8.1.2.2: connection-specific header fields are forbidden in HTTP/2.
                  lower_name = @analyzer.name.downcase
                  if ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade"].include?(lower_name)
                    raise ProtocolException.new("Connection-specific header in HTTP/2: #{@analyzer.name}")
                  end
                  if lower_name == "te" && @analyzer.value.downcase != "trailers"
                    raise ProtocolException.new("TE header with value other than 'trailers': #{@analyzer.value}")
                  end
                  tur.req.headers.add(@analyzer.name, @analyzer.value)
                end
              end

              # § 8.1.2.3: request MUST include :method, :scheme, :path.
              raise ProtocolException.new("Missing :method pseudo-header") if !saw_method
              raise ProtocolException.new("Missing :scheme pseudo-header") if !saw_scheme
              raise ProtocolException.new("Missing :path pseudo-header") if !saw_path

              tur.req.protocol = "HTTP/2.0"
              BayLog.debug("%s H2 read header method=%s protocol=%s uri=%s contlen=%d",
                           ship, tur.req.method, tur.req.protocol, tur.req.uri, tur.req.headers.content_length)

              HttpUtil.check_uri(tur.req.uri)
              req_cont_len = tur.req.headers.content_length

              if req_cont_len > 0
                tur.req.set_limit(req_cont_len)
              end

              begin
                start_tour tur

                if tur.req.headers.content_length <= 0
                  end_req_content(Tour::TOUR_ID_NOCHECK, tur)
                end
              rescue HttpException => e
                BayLog.debug("%s Http error occurred: %s", self, e);
                if req_cont_len <= 0
                  # no post data
                  tur.req.abort
                  tur.res.send_http_exception(Tour::TOUR_ID_NOCHECK, e)

                  return NextSocketAction::CONTINUE
                else
                  # Delay send
                  tur.error = e
                  tur.req.set_content_handler(ReqContentHandler::DEV_NULL)
                  return NextSocketAction::CONTINUE
                end
              end

              return NextSocketAction::CONTINUE
            end
          end
        end
      end
    end
  end
end
