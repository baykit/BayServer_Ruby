require 'baykit/bayserver/protocol/package'
require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/docker/http/h2/h2_type'
require 'baykit/bayserver/docker/http/h2/command/package'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2CommandUnPacker < Baykit::BayServer::Protocol::CommandUnPacker

            include Baykit::BayServer::Agent
            include Baykit::BayServer::Docker::Http::H2::Command

            attr :cmd_handler

            def initialize(cmd_handler)
              @cmd_handler = cmd_handler
            end

            def reset

            end

            def packet_received(pkt)
              BayLog.debug("h2: read packet type=%d strmid=%d len=%d flgs=%s", pkt.type, pkt.stream_id, pkt.data_len(), pkt.flags)

              case pkt.type
              when H2Type::PREFACE
                cmd = CmdPreface.new(pkt.stream_id, pkt.flags)

              when H2Type::HEADERS
                cmd = CmdHeaders.new(pkt.stream_id, pkt.flags)

              when H2Type::PRIORITY
                cmd = CmdPriority.new(pkt.stream_id, pkt.flags)

              when H2Type::SETTINGS
                cmd = CmdSettings.new(pkt.stream_id, pkt.flags)

              when H2Type::WINDOW_UPDATE
                cmd = CmdWindowUpdate.new(pkt.stream_id, pkt.flags)

              when H2Type::DATA
                cmd = CmdData.new(pkt.stream_id, pkt.flags)

              when H2Type::GOAWAY
                cmd = CmdGoAway.new(pkt.stream_id, pkt.flags)

              when H2Type::PING
                cmd = CmdPing.new(pkt.stream_id, pkt.flags)

              when H2Type::RST_STREAM
                cmd = CmdRstStream.new(pkt.stream_id, pkt.flags)

              when H2Type::CONTINUATION
                cmd = CmdContinuation.new(pkt.stream_id, pkt.flags)

              else
                reset()
                raise RuntimeError.new("Invalid Packet: #{pkt}")
              end

              cmd.unpack pkt
              return cmd.handle(@cmd_handler)
            end

          end
        end
      end
    end
  end
end


