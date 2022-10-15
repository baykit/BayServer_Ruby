require 'baykit/bayserver/protocol/command_unpacker'
require 'baykit/bayserver/docker/fcgi/command/package'

module Baykit
  module BayServer
    module Docker
      module Fcgi
        class FcgCommandUnPacker < Baykit::BayServer::Protocol::CommandUnPacker

          include Baykit::BayServer::Docker::Fcgi::Command

          attr :handler

          def initialize(handler)
            @handler = handler
            reset()
          end

          def reset()

          end

          def packet_received(pkt)

            case(pkt.type)
            when FcgType::BEGIN_REQUEST
              cmd = CmdBeginRequest.new(pkt.req_id)

            when FcgType::END_REQUEST
              cmd = CmdEndRequest.new(pkt.req_id)

            when FcgType::PARAMS
              cmd = CmdParams.new(pkt.req_id)

            when FcgType::STDIN
              cmd = CmdStdIn.new(pkt.req_id)

            when FcgType::STDOUT
              cmd = CmdStdOut.new(pkt.req_id)

            when FcgType::STDERR
              cmd = CmdStdErr.new(pkt.req_id)

            else
              raise RuntimeError.new("IllegalState")

            end
            cmd.unpack(pkt)
            cmd.handle(handler)
          end
        end
      end
    end
  end
end

