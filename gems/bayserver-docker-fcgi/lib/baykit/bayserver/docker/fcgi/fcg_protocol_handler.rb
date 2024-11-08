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

          def initialize(fcg_handler, pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, svr_mode)
            super(pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, fcg_handler, svr_mode)
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
