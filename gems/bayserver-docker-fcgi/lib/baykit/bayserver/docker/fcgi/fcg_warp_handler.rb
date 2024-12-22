require 'baykit/bayserver/sink'

require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/tours/package'
require 'baykit/bayserver/agent/next_socket_action'

require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/simple_buffer'
require 'baykit/bayserver/util/cgi_util'

require 'baykit/bayserver/common/warp_data'
require 'baykit/bayserver/docker/fcgi/fcg_protocol_handler'
require 'baykit/bayserver/docker/fcgi/command/package'
require 'baykit/bayserver/docker/fcgi/fcg_params'

module Baykit
  module BayServer
    module Docker
      module Fcgi
        class FcgWarpHandler
          include Baykit::BayServer::Common::WarpHandler # implements
          include FcgHandler

          class WarpProtocolHandlerFactory
            include Baykit::BayServer::Protocol::ProtocolHandlerFactory  # implements
            include Baykit::BayServer::Protocol

            def create_protocol_handler(pkt_store)
              warp_handler =  FcgWarpHandler.new
              cmd_unpacker = FcgCommandUnPacker.new(warp_handler)
              pkt_unpacker = FcgPacketUnPacker.new(pkt_store, cmd_unpacker)
              pkt_packer = PacketPacker.new()
              cmd_packer = CommandPacker.new(pkt_packer, pkt_store)

              proto_handler = FcgProtocolHandler.new(warp_handler, pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, false)
              warp_handler.init(proto_handler)
              return proto_handler
            end
          end

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Util
          include Baykit::BayServer::Common
          include Baykit::BayServer::Docker::Fcgi::Command


          STATE_READ_HEADER = 1
          STATE_READ_CONTENT = 2

          attr :protocol_handler
          attr :cur_warp_id
          attr :state
          attr :line_buf

          attr :pos
          attr :last
          attr :data

          def initialize
            @cur_warp_id = 0
            @line_buf = SimpleBuffer.new
            reset()
          end

          def init(proto_handler)
            @protocol_handler = proto_handler
          end

          def reset
            reset_state
            @line_buf.reset
            @pos = 0
            @last = 0
            @data = nil
          end


          ######################################################
          # Implements WarpHandler
          ######################################################
          def next_warp_id
            @cur_warp_id += 1
            return @cur_warp_id
          end

          def new_warp_data(warp_id)
            return WarpData.new(ship, warp_id)
          end

          ######################################################
          # Implements TourHandler
          ######################################################

          def send_res_headers(tur)
            send_begin_req(tur)
            send_params(tur)
          end

          def send_res_content(tur, buf, start, len, &callback)
            send_stdin(tur, buf, start, len, &callback)
          end

          def send_end_tour(tur, keep_alive, &callback)
            send_stdin(tur, nil, 0, 0, &callback)
          end

          def verify_protocol(proto)
          end

          def on_protocol_error(e)
            raise Sink.new
          end


          ######################################################
          # Implements FcgCommandHandler
          ######################################################

          def handle_begin_request(cmd)
            raise ProtocolException.new("Invalid FCGI command: %d", cmd.type)
          end

          def handle_end_request(cmd) 
            tur = ship.get_tour(cmd.req_id)
            end_req_content(tur)
            NextSocketAction::CONTINUE
          end 

          def handle_params(cmd)
            raise ProtocolException.new("Invalid FCGI command: %d", cmd.type)
          end

          def handle_stderr(cmd)
            msg = cmd.data[cmd.start .. cmd.start + cmd.length + 1]
            BayLog.error("%s server error: %s", self, msg)
            NextSocketAction::CONTINUE
          end

          def handle_stdin(cmd)
            raise ProtocolException.new("Invalid FCGI command: %d", cmd.type)
          end

          def handle_stdout(cmd)
            BayLog.debug("%s handle_stdout req_id=%d len=%d", ship, cmd.req_id, cmd.length)
            #BayLog.debug "#{self} handle_stdout data=#{cmd.data}"

            tur = ship.get_tour(cmd.req_id)
            if tur == nil
              raise Sink.new("Tour not found")
            end

            if cmd.length == 0
              # stdout end
              reset_state
              return NextSocketAction::CONTINUE
            end

            @data = cmd.data
            @pos = cmd.start
            @last = cmd.start + cmd.length

            if @state == STATE_READ_HEADER
              read_header(tur)
            end

            if @pos < @last
              BayLog.debug("%s fcgi: pos=%d last=%d len=%d", ship, @pos, @last, @last - @pos)
              if @state == STATE_READ_CONTENT
                available = tur.res.send_res_content(Tour::TOUR_ID_NOCHECK, @data, @pos, @last - @pos)
                if !available
                  return NextSocketAction::SUSPEND
                end
              end
            end

            NextSocketAction::CONTINUE
          end

          ######################################################
          # Implements FcgCommandHandler
          ######################################################

          ######################################################
          # Custom methods
          ######################################################
          def read_header(tur)
            wdat = WarpData.get(tur)

            header_finished = parse_header(wdat.res_headers)
            if header_finished
              wdat.res_headers.copy_to(tur.res.headers)

              # Check HTTP Status from headers
              status = wdat.res_headers.get(Headers::STATUS)
              #BayLog.debug "#{self} fcgi: status=#{wdat.res_headers.headers}"
              #BayLog.debug "#{self} fcgi: status=#{status}"
              if StringUtil.set?(status)
                stlist = status.split(" ")
                #BayLog.debug("#{self} fcgi: status list=#{stlist}")
                tur.res.headers.status = stlist[0].to_i
                tur.res.headers.remove(Headers::STATUS)
              end

              BayLog.debug("%s fcgi: read header status=%d contlen=%d", ship, tur.res.headers.status, wdat.res_headers.content_length())
              sid = ship.ship_id
              tur.res.set_consume_listener do |len, resume|
                if resume
                  ship.resume_read(sid)
                end
              end

              tur.res.send_headers(Tour::TOUR_ID_NOCHECK)
              change_state(STATE_READ_CONTENT)
            end

          end

          def read_content(tur)
            tur.res.send_res_content(Tour::TOUR_ID_NOCHECK, @data, @pos, @last - @pos)
          end

          def parse_header(headers)

            while true
              if @pos == @last
                # no byte data
                break
              end

              c = @data[@pos]
              @pos += 1

              if c == CharUtil::CR
                next
              elsif c == CharUtil::LF
                line = @line_buf.buf

                if line.length == 0
                  return true
                end

                colon_pos = line.index(':')
                if colon_pos == nil
                  raise ProtocolException.new("fcgi: Header line of server is invalid: %s", line)
                else
                  name = line[0 .. colon_pos - 1].strip
                  value = line[colon_pos + 1 .. -1].strip

                  if StringUtil.empty?(name) || StringUtil.empty?(value)
                    raise ProtocolException("fcgi: Header line of server is invalid: %s", line)
                  end

                  headers.add(name, value)
                  if BayServer.harbor.trace_header
                    BayLog.info("%s fcgi_warp: resHeader: %s=%s", ship, name, value)
                  end
                end
                @line_buf.reset()
              else
                @line_buf.put(c)
              end
            end
            false
          end

          def end_req_content(tur)
            ship.end_warp_tour(tur, true)
            tur.res.end_res_content(Tour::TOUR_ID_NOCHECK)
            reset_state()
          end

          def change_state(new_state)
            @state = new_state
          end

          def reset_state()
            change_state(STATE_READ_HEADER)
          end


          def send_stdin(tur, data, ofs, len, &callback)
            cmd = CmdStdIn.new(WarpData.get(tur).warp_id, data, ofs, len)
            ship.post(cmd, &callback)
          end

          def send_begin_req(tur)
            cmd = CmdBeginRequest.new(WarpData.get(tur).warp_id)
            cmd.role = CmdBeginRequest::FCGI_RESPONDER
            cmd.keep_conn = true
            ship.post(cmd)
          end

          def send_params(tur)
            script_base = ship.docker.script_base
            if script_base == nil
              script_base = tur.town.location
            end

            if StringUtil.empty?(script_base)
              raise StandardError.new("#{tur.town} Could not create SCRIPT_FILENAME. Location of town not specified.")
            end

            doc_root = ship.docker.doc_root
            if doc_root == nil
              doc_root = tur.town.location
            end

            if StringUtil.empty?(doc_root)
              raise StandardError.new("#{tur.town} docRoot of fcgi docker or location of town is not specified.")
            end

            warp_id = WarpData.get(tur).warp_id
            cmd = CmdParams.new(warp_id)
            script_fname = nil
            CgiUtil.get_env(tur.town.name, doc_root, script_base, tur) do |name, value|
              if name == CgiUtil::SCRIPT_FILENAME
                script_fname = value
              else
                cmd.add_param(name, value)
              end
            end

            script_fname = "proxy:fcgi://#{ship.docker.host}:#{ship.docker.port}#{script_fname}"
            cmd.add_param(CgiUtil::SCRIPT_FILENAME, script_fname)

            # Add FCGI params
            cmd.add_param(FcgParams::CONTEXT_PREFIX, "")
            cmd.add_param(FcgParams::UNIQUE_ID, DateTime.now.to_s)
            #cmd.add_param(FcgParams::X_FORWARDED_FOR, tur.req.remote_address)
            #cmd.add_param(FcgParams::X_FORWARDED_PROTO, tur.is_secure ? "https" : "http")
            #cmd.add_param(FcgParams::X_FORWARDED_PORT, tur.req.req_port.to_s)

            if BayServer.harbor.trace_header
              cmd.params.each do |kv|
                BayLog.info("%s fcgi_warp: env: %s=%s", ship, kv[0], kv[1])
              end
            end

            ship.post(cmd)

            cmd_params_end = CmdParams.new(WarpData.get(tur).warp_id)
            ship.post(cmd_params_end)
          end

          def ship
            return @protocol_handler.ship
          end
        end
      end
    end
  end
end
