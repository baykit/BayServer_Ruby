require 'baykit/bayserver/protocol/protocol_handler'
require 'baykit/bayserver/protocol/packet_store'
require 'baykit/bayserver/util/headers'
require 'baykit/bayserver/docker/http/h1/command/package'
require 'baykit/bayserver/docker/http/h1/h1_packet'

module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          class H1ProtocolHandler < Baykit::BayServer::Protocol::ProtocolHandler
            include Baykit::BayServer::Docker::Http::H1::H1CommandHandler # implements

            include Baykit::BayServer::Agent
            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Util
            include Baykit::BayServer::Docker::Http::H1
            include Baykit::BayServer::Docker::Http::H1::Command

            attr :keeping

            def initialize(pkt_store, svr_mode)
              @command_unpacker = H1CommandUnPacker.new(self, svr_mode)
              @packet_unpacker = H1PacketUnPacker.new(@command_unpacker, pkt_store)
              @packet_packer = PacketPacker.new()
              @command_packer = CommandPacker.new(@packet_packer, pkt_store)
              @server_mode = svr_mode
              @keeping = false
            end

            def inspect()
              return @ship.inspect()
            end

            ######################################################
            # Implements Reusable
            ######################################################

            def reset
              super
              @keeping = false
            end

            ######################################################
            # Implements ProtocolHandler
            ######################################################

            def max_req_packet_data_size
              return H1Packet::MAX_DATA_LEN
            end

            def max_res_packet_data_size
              return H1Packet::MAX_DATA_LEN
            end

            def protocol
              return HtpPortDocker::H1_PROTO_NAME
            end

          end
        end
      end
    end
  end
end
