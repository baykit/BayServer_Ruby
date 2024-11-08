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


            def initialize(h2_handler, pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, svr_mode)
              super(pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, h2_handler, svr_mode)
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
