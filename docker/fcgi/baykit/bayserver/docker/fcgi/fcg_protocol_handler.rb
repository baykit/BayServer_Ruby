require 'baykit/bayserver/protocol/package'
require 'baykit/bayserver/tours/package'

require 'baykit/bayserver/util/http_util'
require 'baykit/bayserver/util/simple_buffer'

require 'baykit/bayserver/docker/fcgi/command/package'
require 'baykit/bayserver/docker/fcgi/package'


module Baykit
  module BayServer
    module Docker
      module Fcgi
        class FcgProtocolHandler < Baykit::BayServer::Protocol::ProtocolHandler
          include Baykit::BayServer::Docker::Fcgi::FcgCommandHandler # implements

          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Docker::Fcgi::Command

          def initialize(pkt_store, svr_mode)
            @command_unpacker = FcgCommandUnPacker.new(self)
            @packet_unpacker = FcgPacketUnPacker.new(pkt_store, @command_unpacker)
            @packet_packer = PacketPacker.new()
            @command_packer = CommandPacker.new(@packet_packer, pkt_store)
            @server_mode = svr_mode
          end

          def inspect()
            return "PH[#{@ship}]"
          end

          ######################################################
          # Implements ProtocolHandler
          ######################################################
          def protocol()
            return FcgDocker::PROTO_NAME
          end

          def max_req_packet_data_size
            FcgPacket::MAXLEN
          end

          def max_res_packet_data_size
            FcgPacket::MAXLEN
          end

        end
      end
    end
  end
end
