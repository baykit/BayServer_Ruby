require 'baykit/bayserver/common/warp_handler'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/docker/http/h2/command/package'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2WarpHandler
            include Baykit::BayServer::Common::WarpHandler # implements
            include H2Handler # implements

            class WarpProtocolHandlerFactory
              include Baykit::BayServer::Protocol::ProtocolHandlerFactory  # implements

              include Baykit::BayServer::Protocol

              def create_protocol_handler(pkt_store)
                warp_handler = H2WarpHandler.new
                cmd_unpacker = H2CommandUnPacker.new(warp_handler)
                # serverMode=false on the warp side: we send the preface, we don't expect to receive it.
                pkt_unpacker = H2PacketUnPacker.new(cmd_unpacker, pkt_store, false)
                pkt_packer = PacketPacker.new()
                cmd_packer = CommandPacker.new(pkt_packer, pkt_store)

                proto_handler = H2ProtocolHandler.new(warp_handler, pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, false)
                warp_handler.init(proto_handler)
                return proto_handler
              end
            end

            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Agent
            include Baykit::BayServer::Common
            include Baykit::BayServer::Tours
            include Baykit::BayServer::Util
            include Baykit::BayServer::Docker::Http::H2::Command

            # 16 MiB advertised stream + connection window. Far above any single
            # bench body; reactive WINDOW_UPDATEs in handle_data top it back up.
            INITIAL_WINDOW_SIZE_OUT = 16 * 1024 * 1024

            attr :protocol_handler
            attr :analyzer
            attr :req_header_tbl
            attr :res_header_tbl
            attr :cur_stream_id

            def initialize
              @analyzer = HeaderBlockAnalyzer.new
              @req_header_tbl = HeaderTable.create_dynamic_table()
              @res_header_tbl = HeaderTable.create_dynamic_table()
              @cur_stream_id = 1
              @prelude_sent = false
            end

            def init(proto_handler)
              @protocol_handler = proto_handler
            end

            def to_s
              ship.to_s
            end

            ######################################################
            # Implements Reusable
            ######################################################

            def reset()
              @cur_stream_id = 1
              @prelude_sent = false
            end

            ######################################################
            # Implements WarpHandler
            ######################################################
            def next_warp_id
              # Client-initiated H2 streams use odd ids: 1, 3, 5, ...
              cur = @cur_stream_id
              @cur_stream_id += 2
              return cur
            end

            def new_warp_data(warp_id)
              return WarpData.new(ship, warp_id)
            end

            def send_res_headers(tur)
              send_prelude_if_needed
              send_req_header_command(tur)
            end

            def send_res_content(tur, buf, start, len, &callback)
              send_req_data_command(tur, buf, start, len, &callback)
            end

            def send_end_tour(tur, keep_alive, &lis)
              # If the request had no body, send_req_headers already set END_STREAM
              # on the final HEADERS/CONTINUATION frame. Sending another empty
              # DATA frame with END_STREAM here would be a frame on an already-
              # half-closed stream and backends respond with RST_STREAM
              # (STREAM_CLOSED, code 5). In that case just notify the consumer
              # listener so the deferred-write callback is satisfied.
              req_had_body = tur.req.headers.contains("content-length") ||
                             tur.req.headers.contains("transfer-encoding")
              if !req_had_body
                lis.call(true) if lis
                return
              end
              stream_id = WarpData.get(tur).warp_id
              cmd = CmdData.new(stream_id, nil, [], 0, 0)
              cmd.flags.set_end_stream(true)
              ship.post(cmd, true, &lis)
            end

            def verify_protocol(proto)
              # No-op: H2WarpHandler forces H2 from the start.
            end

            def max_multiplexed_tours
              # H2 supports stream multiplexing on a shared TCP connection.
              # 100 is a conservative starting point.
              100
            end

            ######################################################
            # Implements H2CommandHandler
            ######################################################
            def handle_preface(cmd)
              # Client side never receives a preface: only servers do.
              raise Sink.new("Illegal State")
            end

            def handle_data(cmd)
              BayLog.debug("%s handle_data: stm=#{cmd.stream_id} len=#{cmd.length}", ship)
              tur = ship.get_tour(cmd.stream_id)
              if tur == nil
                BayLog.error("%s no tour for streamId=%d", ship, cmd.stream_id)
                return NextSocketAction::CONTINUE
              end
              available = tur.res.send_res_content(Tour::TOUR_ID_NOCHECK, cmd.data, cmd.start, cmd.length)

              # Replenish flow-control windows so the upstream backend can keep sending.
              # Without this the connection-level + stream-level windows (default 65535 each)
              # drain after ~65 KB of body and the backend stops sending DATA frames.
              # Only send per-stream WINDOW_UPDATE when END_STREAM is NOT set:
              # once the peer has flagged END_STREAM the stream is closed and a strict
              # server (nginx) responds with RST_STREAM STREAM_CLOSED.
              # Connection-level (streamId=0) WINDOW_UPDATE is always emitted.
              if cmd.length > 0
                if !cmd.flags.end_stream?
                  upd = CmdWindowUpdate.new(cmd.stream_id)
                  upd.window_size_increment = cmd.length
                  ship.post(upd, false)
                end
                upd2 = CmdWindowUpdate.new(0)
                upd2.window_size_increment = cmd.length
                ship.post(upd2, true)
              end

              if !available
                return NextSocketAction::SUSPEND
              end

              if cmd.flags.end_stream?
                end_res_content(tur)
              end

              return NextSocketAction::CONTINUE
            end

            def handle_headers(cmd)
              BayLog.debug("%s handle_headers: stm=#{cmd.stream_id} dep=#{cmd.stream_dependency} weight=#{cmd.weight}", ship)

              tur = ship.get_tour(cmd.stream_id)
              if tur == nil
                BayLog.error("%s no tour for streamId=%d", ship, cmd.stream_id)
                return NextSocketAction::CONTINUE
              end
              wdat = WarpData.get(tur)

              if tur.res.header_sent
                raise ProtocolException.new("Header command not expected")
              end

              begin
                header_blocks = HeaderBlockParser.new(cmd.data, cmd.start, cmd.length).parse_header_blocks()
              rescue RuntimeError => e
                raise ProtocolException.new("HPACK decode failed: #{e.message}")
              end

              header_blocks.each do |blk|
                if blk.op == HeaderBlock::UPDATE_DYNAMIC_TABLE_SIZE
                  @res_header_tbl.set_size(blk.size)
                  next
                end
                @analyzer.analyze_header_block(blk, @res_header_tbl)
                next if @analyzer.name == nil

                if @analyzer.name[0] != ':'
                  tur.res.headers.add(@analyzer.name, @analyzer.value)
                elsif @analyzer.raw_name == HeaderTable::PSEUDO_HEADER_STATUS
                  begin
                    tur.res.headers.status = Integer(@analyzer.value)
                  rescue ArgumentError => e
                    BayLog.error_e(e)
                  end
                end
                # other pseudo-headers in a response are ignored (peer is trusted)
              end

              if cmd.flags.end_headers?
                tur.res.send_headers(Tour::TOUR_ID_NOCHECK)

                # Wire up the back-pressure resume hook (mirrors H1WarpHandler):
                # the consumer listener fires when the downstream write buffer drains;
                # on resume==true we ask the warp ship to read more from the backend.
                # Without this, send_res_content's internal consumed() callback finds
                # res_consume_listener=nil and tears the agent down with
                # "Consume listener is null".
                if !cmd.flags.end_stream?
                  wsip = ship
                  sid = wsip.id()
                  tur.res.set_consume_listener do |len, resume|
                    if resume
                      wsip.resume_read(sid)
                    end
                  end
                end

                if cmd.flags.end_stream?
                  end_res_content(tur)
                end
              end

              return NextSocketAction::CONTINUE
            end

            def handle_priority(cmd)
              # PRIORITY frames are deprecated in RFC 9113; we don't act on them.
              return NextSocketAction::CONTINUE
            end

            def handle_settings(cmd)
              BayLog.debug("%s handle_settings: stmid=%d", ship, cmd.stream_id)
              # On the warp (client) side we receive the server's SETTINGS.
              # Acknowledge it and move on.
              if !cmd.flags.ack?
                ack = CmdSettings.new(0, H2Flags.new(H2Flags::FLAGS_ACK))
                ship.post(ack, true)
              end
              return NextSocketAction::CONTINUE
            end

            def handle_window_update(cmd)
              BayLog.debug("%s handle_window_update: stmid=%d size=%d", ship, cmd.stream_id, cmd.window_size_increment)
              return NextSocketAction::CONTINUE
            end

            def handle_go_away(cmd)
              # GOAWAY (RFC 9113 §6.8). Common case is errorCode == NO_ERROR (0)
              # when the peer hits its per-connection request budget and wants to rotate.
              if cmd.error_code == 0
                BayLog.debug("%s received GoAway (NO_ERROR, lastStreamId=%d)", ship, cmd.last_stream_id)
              else
                BayLog.error("#{ship} received GoAway: code=#{cmd.error_code} " +
                             "desc=#{H2ErrorCode.msg.get(cmd.error_code.to_s.to_sym)} " +
                             "debug=#{cmd.debug_data}")
              end
              # Exclude this ship from the multiplex pool so no further tours attach,
              # then close. Letting in-flight tours drain rarely works because
              # peers send GOAWAY immediately followed by FIN.
              ship.docker.exclude_from_pool(ship) if ship.docker.respond_to?(:exclude_from_pool)
              ship.notify_service_unavailable("Received GoAway packet")
              return NextSocketAction::CLOSE
            end

            def handle_ping(cmd)
              BayLog.debug("%s handle_ping: stm=%d", ship, cmd.stream_id)
              return NextSocketAction::CONTINUE
            end

            def handle_rst_stream(cmd)
              BayLog.debug("%s handle_rst_stream: stm=%d code=%d", ship, cmd.stream_id, cmd.error_code)
              tur = ship.get_tour(cmd.stream_id, false)
              if tur != nil
                tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::SERVICE_UNAVAILABLE,
                                   "RST_STREAM received: code=#{cmd.error_code}")
              end
              return NextSocketAction::CONTINUE
            end

            def handle_continuation(cmd)
              # We do not currently split inbound HEADERS across CONTINUATION frames.
              # If a backend chooses to use CONTINUATION the response will be malformed;
              # treat it as a no-op for now.
              return NextSocketAction::CONTINUE
            end

            private

            def ship
              return @protocol_handler.ship
            end

            # Send the H2 connection prelude (RFC 7540 § 3.5):
            #   1. The 24-byte client connection preface
            #   2. An initial SETTINGS frame
            #   3. A connection-level WINDOW_UPDATE
            # Called lazily on the first send_req_headers so it runs after the
            # TCP connect completes.
            def send_prelude_if_needed
              return if @prelude_sent

              # 1. Connection preface — CmdPreface#pack emits raw 24-byte preface.
              # Use ship.post (not protocol_handler.post): WarpShip.post buffers
              # commands in cmd_buf while !connected and drains them via flush()
              # after notify_connect.
              preface = CmdPreface.new(0, nil)
              ship.post(preface, false)

              # 2. Initial SETTINGS frame on the control stream (id=0), no ACK.
              set = CmdSettings.new(H2ProtocolHandler::CTL_STREAM_ID)
              set.stream_id = 0
              set.items.append(CmdSettings::Item.new(CmdSettings::MAX_CONCURRENT_STREAMS,
                [BayServer.harbor.max_tours_per_ship, 100].max))
              set.items.append(CmdSettings::Item.new(CmdSettings::INITIAL_WINDOW_SIZE,
                INITIAL_WINDOW_SIZE_OUT))
              ship.post(set, false)

              # 3. Connection-level WINDOW_UPDATE: bump stream 0's window so
              #    multi-MB bodies aren't rate-limited by the connection window
              #    before our reactive WINDOW_UPDATEs in handle_data kick in.
              conn_up = CmdWindowUpdate.new(0)
              conn_up.window_size_increment = INITIAL_WINDOW_SIZE_OUT
              ship.post(conn_up, false)

              @prelude_sent = true
            end

            def send_req_header_command(tur)
              twn = tur.town
              twn_path = twn.name
              if !twn_path.end_with?("/")
                twn_path += "/"
              end
              sip = ship
              new_uri = sip.docker.warp_base + tur.req.uri[twn_path.length .. -1]

              bld = HeaderBlockBuilder.new
              header_blocks = []

              header_blocks << bld.build_header_block(HeaderTable::PSEUDO_HEADER_METHOD, tur.req.method, @req_header_tbl)
              header_blocks << bld.build_header_block(HeaderTable::PSEUDO_HEADER_PATH, new_uri, @req_header_tbl)
              header_blocks << bld.build_header_block(HeaderTable::PSEUDO_HEADER_SCHEME,
                tur.is_secure ? "https" : "http", @req_header_tbl)
              header_blocks << bld.build_header_block(HeaderTable::PSEUDO_HEADER_AUTHORITY,
                "#{sip.docker.host}:#{sip.docker.port}", @req_header_tbl)

              # Regular request headers: must be lowercase, must not include
              # connection-specific fields (RFC 7540 § 8.1.2.2).
              tur.req.headers.names.each do |name|
                lower = name.downcase
                next if ["connection", "host", "keep-alive", "transfer-encoding",
                         "upgrade", "proxy-connection"].include?(lower)
                tur.req.headers.values(name).each do |value|
                  header_blocks << bld.build_header_block(lower, value, @req_header_tbl)
                end
              end

              buf = SimpleBuffer.new
              HeaderBlockRenderer.new(buf).render_header_blocks(header_blocks)

              stream_id = WarpData.get(tur).warp_id
              end_stream = !tur.req.headers.contains("content-length") &&
                           !tur.req.headers.contains("transfer-encoding")

              pos = 0
              len = buf.length
              # Always emit at least one HEADERS frame.
              if len == 0
                hcmd = CmdHeaders.new(stream_id)
                hcmd.excluded = false
                hcmd.data = buf.bytes
                hcmd.start = 0
                hcmd.length = 0
                hcmd.flags.set_end_headers(true)
                hcmd.flags.set_end_stream(true) if end_stream
                sip.post(hcmd, true)
                return
              end

              while len > 0
                chunk_len = [len, H2Packet::DEFAULT_PAYLOAD_MAXLEN].min

                if pos == 0
                  cmd = CmdHeaders.new(stream_id)
                  cmd.excluded = false
                else
                  cmd = CmdContinuation.new(stream_id)
                end
                cmd.data = buf.bytes
                cmd.start = pos
                cmd.length = chunk_len
                cmd.flags.set_padded(false)

                pos += chunk_len
                len -= chunk_len
                if len == 0
                  cmd.flags.set_end_headers(true)
                  # Mark end-of-stream on the final HEADERS/CONTINUATION when
                  # there's no request body; otherwise send_end_tour will close it.
                  cmd.flags.set_end_stream(true) if end_stream
                end
                # Use ship.post: it buffers when !connected (during start_warp_tour,
                # before notify_connect fires). Flush only on the last frame.
                sip.post(cmd, len == 0)
              end
            end

            def send_req_data_command(tur, buf, start, len, &lis)
              stream_id = WarpData.get(tur).warp_id
              cmd = CmdData.new(stream_id, nil, buf, start, len)
              ship.post(cmd, true, &lis)
            end

            def end_res_content(tur)
              # Order matters: end_warp_tour reads WarpData.get(tur) (= the
              # tour's req content_handler). tur.res.end_res_content triggers
              # tour.reset() which clears that content_handler, so we must
              # close out the warp side first. Mirrors H1WarpHandler.end_res_content.
              ship.end_warp_tour(tur, true)
              tur.res.end_res_content(Tour::TOUR_ID_NOCHECK)
            end
          end
        end
      end
    end
  end
end
