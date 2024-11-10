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
            include Baykit::BayServer::WaterCraft
            include Baykit::BayServer::Tours
            include Baykit::BayServer::Util
            include Baykit::BayServer::Docker::Http::H2::Command

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

            def initialize
              @window_size = BayServer.harbor.tour_buffer_size
              @settings = H2Settings.new
              @analyzer = HeaderBlockAnalyzer.new
              @req_header_tbl = HeaderTable.create_dynamic_table()
              @res_header_tbl = HeaderTable.create_dynamic_table()
            end

            ######################################################
            # implements Reusable
            ######################################################

            def reset()
              @header_read = false
              @req_cont_len = 0
              @req_cont_read = 0
            end

            def init(proto_handler)
              @protocol_handler = proto_handler
            end

            ######################################################
            # implements InboundHandler
            ######################################################

            def send_res_headers(tur)
              cmd = CmdHeaders.new(tur.req.key)
              bld = HeaderBlockBuilder.new()
              blk = bld.build_header_block(":status", tur.res.headers.status.to_s, @res_header_tbl)
              cmd.header_blocks << blk

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
                    cmd.header_blocks.append(blk)
                  end
                end
              end

              cmd.flags.set_end_headers(true)
              cmd.excluded = true
              cmd.flags.set_padded(false)
              @protocol_handler.post(cmd)
            end

            def send_res_content(tur, bytes, ofs, len, &callback)
              BayLog.debug("%s send_res_content len=%d", self, len)
              cmd = CmdData.new(tur.req.key, nil, bytes, ofs, len);
              @protocol_handler.post(cmd, &callback)
            end

            def send_end_tour(tur, keep_alive, &callback)
              BayLog.debug("%s send_end_tour. keep=%s", self, keep_alive)
              cmd = CmdData.new(tur.req.key, nil, [], 0, 0)
              cmd.flags.set_end_stream(true)
              @protocol_handler.post(cmd, &callback)
            end

            def on_protocol_error(err)
              BayLog.error_e err
              cmd = CmdGoAway.new(CTL_STREAM_ID)
              cmd.stream_id = CTL_STREAM_ID
              cmd.last_stream_id = CTL_STREAM_ID
              cmd.error_code = H2ErrorCode::PROTOCOL_ERROR
              cmd.debug_data = "Thank you!"
              begin
                @protocol_handler.post(cmd)
                @protocol_handler.end(ship)
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
              set.items.append(CmdSettings::Item.new(CmdSettings::MAX_CONCURRENT_STREAMS, TourStore::MAX_TOURS))
              set.items.append(CmdSettings::Item.new(CmdSettings::INITIAL_WINDOW_SIZE, @window_size))
              @protocol_handler.post(set)

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

              cmd.header_blocks.each do |blk|
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

                elsif @analyzer.name[0] != ":"
                  tur.req.headers.add(@analyzer.name, @analyzer.value)

                elsif @analyzer.method != nil
                  tur.req.method = @analyzer.method

                elsif @analyzer.path != nil
                  tur.req.uri = @analyzer.path

                elsif @analyzer.scheme != nil

                elsif @analyzer.status != nil
                  raise RuntimeError.new("Illegal State")
                end
              end

              if cmd.flags.end_headers?
                tur.req.protocol = "HTTP/2.0"
                BayLog.debug("%s H2 read header method=%s protocol=%s uri=%s contlen=%d",
                             ship, tur.req.method, tur.req.protocol, tur.req.uri, tur.req.headers.content_length)

                req_cont_len = tur.req.headers.content_length()

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

              end

              NextSocketAction::CONTINUE
            end

            def handle_data(cmd)
              BayLog.debug("%s handle_data: stm=%d len=%d", ship, cmd.stream_id, cmd.length)

              tur = get_tour(cmd.stream_id)
              if tur == nil
                raise RuntimeError.new("Invalid stream id: #{cmd.stream_id}")
              end
              if tur.req.headers.content_length <= 0
                raise ProtocolException.new("Post content not allowed")
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
                        @protocol_handler.post(upd)
                        @protocol_handler.post(upd2)
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
                  @settings.enable_push = (item.value != 0)

                when CmdSettings::MAX_CONCURRENT_STREAMS
                  @settings.max_concurrent_streams = item.value

                when CmdSettings::INITIAL_WINDOW_SIZE
                  @settings.initial_window_size = item.value

                when CmdSettings::MAX_FRAME_SIZE
                  @settings.max_frame_size = item.value

                when CmdSettings::MAX_HEADER_LIST_SIZE
                  @settings.max_header_list_size = item.value

                else
                  BayLog.debug("Invalid settings id (Ignore): %d", item.id)

                end
              end

              res = CmdSettings.new(0, H2Flags.new(H2Flags::FLAGS_ACK))
              @protocol_handler.post(res)
              return NextSocketAction::CONTINUE
            end

            def handle_window_update(cmd)
              BayLog.debug("%s handleWindowUpdate: stmid=%d siz=%d", ship,  cmd.stream_id, cmd.window_size_increment);

              if cmd.window_size_increment == 0
                raise ProtocolException.new("Invalid increment value")
              end

              window_size = cmd.window_size_increment
              return NextSocketAction::CONTINUE
            end

            def handle_go_away(cmd)
              BayLog.debug("%s received GoAway: lastStm=%d code=%d desc=%s debug=%s",
                           ship, cmd.last_stream_id, cmd.error_code, H2ErrorCode.msg.get(cmd.error_code.to_s.to_sym), cmd.debug_data);
              return NextSocketAction::CLOSE
            end

            def handle_ping(cmd)
              BayLog.debug("%s handle_ping: stm=%d", ship, cmd.stream_id)

              res = CmdPing.new(cmd.stream_id, H2Flags.new(H2Flags::FLAGS_ACK), cmd.opaque_data)
              @protocol_handler.post(res)
              return NextSocketAction::CONTINUE
            end

            def handle_rst_stream(cmd)
              BayLog.warn("%s received RstStream: stmid=%d code=%d desc=%s",
                           ship, cmd.stream_id, cmd.error_code, H2ErrorCode.msg.get(cmd.error_code.to_s.to_sym))
              tur = get_tour(cmd.stream_id)
              if tur == nil
                BayLog.warn("%s stream not found id=%d", ship, cmd.stream_id)
              else
                tur.req.abort
                return NextSocketAction::CONTINUE
              end
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
                remote_addr = skt.getpeername()
                tur.req.remote_port, tur.req.remote_address = Socket.unpack_sockaddr_in(remote_addr)
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

          end
        end
      end
    end
  end
end
