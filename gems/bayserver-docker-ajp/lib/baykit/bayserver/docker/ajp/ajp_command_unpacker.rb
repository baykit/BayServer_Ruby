require 'baykit/bayserver/protocol/command_unpacker'
require 'baykit/bayserver/docker/ajp/ajp_type'
require 'baykit/bayserver/docker/ajp/command/package'

module Baykit
  module BayServer
    module Docker
      module Ajp
        class AjpCommandUnPacker <Baykit::BayServer::Protocol::CommandUnPacker

          include Baykit::BayServer::Docker::Ajp::Command

          attr :cmd_handler

          def initialize(handler)
            @cmd_handler = handler
            reset
          end

          def reset()
          end

          def packet_received(pkt)

            BayLog.debug("ajp:  packet received: type=%d datalen=%d", pkt.type, pkt.data_len)

            case pkt.type
            when AjpType::DATA
              cmd = CmdData.new

            when AjpType::FORWARD_REQUEST
              cmd = CmdForwardRequest.new

            when AjpType::SEND_BODY_CHUNK
              cmd = CmdSendBodyChunk.new(pkt.buf, pkt.header_len, pkt.data_len)

            when AjpType::SEND_HEADERS
              cmd = CmdSendHeaders.new

            when AjpType::END_RESPONSE
              cmd = CmdEndResponse.new

            when AjpType::SHUTDOWN
              cmd = CmdShutdown.new

            when AjpType::GET_BODY_CHUNK
              cmd = CmdGetBodyChunk.new

            else
              raise Sink.new()
            end

            cmd.unpack(pkt)
            return cmd.handle(@cmd_handler)   # visit
          end

          def need_data()
            return @cmd_handler.need_data()
          end

        end
      end
    end
  end
end

