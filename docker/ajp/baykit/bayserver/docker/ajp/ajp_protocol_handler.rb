require 'baykit/bayserver/protocol/protocol_handler'
require 'baykit/bayserver/protocol/packet_store'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/tours/package'
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
          include Baykit::BayServer::Util
          include Baykit::BayServer::Docker::Ajp::Command


          def initialize(pkt_store, svr_mode)
            @command_unpacker = AjpCommandUnPacker.new(self)
            @packet_unpacker = AjpPacketUnPacker.new(pkt_store, @command_unpacker)
            @packet_packer = PacketPacker.new()
            @command_packer = CommandPacker.new(@packet_packer, pkt_store)
            @server_mode = svr_mode
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

