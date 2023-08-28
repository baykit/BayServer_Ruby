require 'baykit/bayserver/protocol/protocol_handler'
require 'baykit/bayserver/protocol/packet_store'
require 'baykit/bayserver/util/headers'
require 'baykit/bayserver/docker/http/h2/command/package'
require 'baykit/bayserver/docker/http/h2/h2_packet'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2ProtocolHandler < Baykit::BayServer::Protocol::ProtocolHandler
            include Baykit::BayServer::Docker::Http::H2::H2CommandHandler  # implements

            include Baykit::BayServer::Agent
            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Util
            include Baykit::BayServer::Docker::Http::H2::Command
            include Baykit::BayServer::Docker::Http::H2

            CTL_STREAM_ID = 0

            attr :req_header_tbl
            attr :res_header_tbl

            def initialize(pkt_store, svr_mode)
              @command_unpacker = H2CommandUnPacker.new(self)
              @packet_unpacker = H2PacketUnPacker.new(@command_unpacker, pkt_store, svr_mode)
              @packet_packer = PacketPacker.new()
              @command_packer = CommandPacker.new(@packet_packer, pkt_store)
              @server_mode = svr_mode
              @req_header_tbl = HeaderTable.create_dynamic_table()
              @res_header_tbl = HeaderTable.create_dynamic_table()
            end

            ######################################################
            # Implements ProtocolHandler
            ######################################################

            def max_req_packet_data_size
              H2Packet::DEFAULT_PAYLOAD_MAXLEN
            end

            def max_res_packet_data_size
              H2Packet::DEFAULT_PAYLOAD_MAXLEN
            end

            def protocol
              return HtpPortDocker::H2_PROTO_NAME
            end


          end
        end
      end
    end
  end
end
