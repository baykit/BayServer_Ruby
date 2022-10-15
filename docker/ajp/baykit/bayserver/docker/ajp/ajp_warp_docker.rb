require 'baykit/bayserver/docker/warp/warp_docker'
require 'baykit/bayserver/docker/ajp/package'
require 'baykit/bayserver/agent/transporter/plain_transporter'
require 'baykit/bayserver/protocol/packet_store'

module Baykit
  module BayServer
    module Docker
      module Ajp
        class AjpWarpDocker < Baykit::BayServer::Docker::Warp::WarpDocker
          include Baykit::BayServer::Docker::Ajp::AjpDocker  # implements

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Agent::Transporter

          ######################################################
          # Implements WarpDocker
          ######################################################
          def secure()
            return false
          end

          ######################################################
          # Implements WarpDockerBase
          ######################################################
          private
          def protocol()
            return PROTO_NAME
          end

          def new_transporter(agt, skt)
            PlainTransporter.new(false, IOUtil.get_sock_recv_buf_size(skt))
          end

          ######################################################
          # Class initializer
          ######################################################
          begin
            PacketStore.register_protocol(
              PROTO_NAME,
              AjpPacketFactory.new()
            )
            ProtocolHandlerStore.register_protocol(
              PROTO_NAME,
              false,
              AjpWarpHandler::WarpProtocolHandlerFactory.new())
          end
        end
      end
    end
  end
end

