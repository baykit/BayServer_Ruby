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

            include Baykit::BayServer::Agent
            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Util
            include Baykit::BayServer::Docker::Http::H1
            include Baykit::BayServer::Docker::Http::H1::Command

            attr :keeping

            def initialize(h1_handler, pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, svr_mode)
              super(pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, h1_handler, svr_mode)
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
