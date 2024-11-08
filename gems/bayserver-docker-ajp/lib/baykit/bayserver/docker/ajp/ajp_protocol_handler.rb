require 'baykit/bayserver/protocol/protocol_handler'
require 'baykit/bayserver/docker/ajp/package'
require 'baykit/bayserver/docker/ajp/command/package'

module Baykit
  module BayServer
    module Docker
      module Ajp
        class AjpProtocolHandler < Baykit::BayServer::Protocol::ProtocolHandler
          include Baykit::BayServer::Docker::Ajp::AjpCommandHandler # implements

          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Docker::Ajp::Command


          def initialize(ajp_handler, pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, svr_mode)
            super(pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, ajp_handler, svr_mode)
          end

          def to_s
            "pch[#{@ship}]"
          end

          ######################################################
          # Implements ProtocolHandler
          ######################################################

          def protocol()
            return AjpDocker::PROTO_NAME
          end

          def max_req_packet_data_size()
            return CmdData::MAX_DATA_LEN
          end

          def max_res_packet_data_size()
            return CmdSendBodyChunk::MAX_CHUNKLEN
          end


        end
      end
    end
  end
end

