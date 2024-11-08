require 'baykit/bayserver/sink'
require 'baykit/bayserver/protocol/package'
require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/docker/http/h1/package'
require 'baykit/bayserver/docker/http/h1/command/package'

module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          class H1CommandUnPacker < Baykit::BayServer::Protocol::CommandUnPacker

            include Baykit::BayServer::Agent
            include Baykit::BayServer::Docker::Http::H1::Command

            attr :command_handler
            attr :server_mode

            def initialize(cmd_handler, svr_mode)
              @cmd_handler = cmd_handler
              @server_mode = svr_mode
            end

            def reset

            end

            def packet_received(pkt)
              BayLog.debug("h1: read packet type=%d length=%d", pkt.type, pkt.data_len())

              case pkt.type
              when H1Type::HEADER
                cmd = CmdHeader.new(@server_mode)

              when H1Type::CONTENT
                cmd = CmdContent.new()

              else
                reset
                raise Sink.new("IllegalState")
              end

              cmd.unpack pkt
              return cmd.handle(@cmd_handler)
            end

            def finished()
              return @cmd_handler.req_finished()
            end
          end
        end
      end
    end
  end
end


