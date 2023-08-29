require 'baykit/bayserver/docker/base/port_base'
require 'baykit/bayserver/protocol/packet_store'
require 'baykit/bayserver/docker/fcgi/package'


module Baykit
  module BayServer
    module Docker
      module Fcgi
        class FcgPortDocker < Baykit::BayServer::Docker::Base::PortBase
          include Baykit::BayServer::Docker::Fcgi::FcgDocker # implements

          include Baykit::BayServer::Protocol
          include Baykit::BayServer::WaterCraft
          include Baykit::BayServer::Docker::Base

          ######################################################
          # Implements Port
          ######################################################
          def protocol()
            return PROTO_NAME
          end

          ######################################################
          # Implements PortBase
          ######################################################
          def support_anchored()
            return true
          end

          def support_unanchored()
            return false
          end

          ######################################################
          # Class initializer
          ######################################################
          begin
            PacketStore.register_protocol(
              PROTO_NAME,
              FcgPacketFactory.new())
            ProtocolHandlerStore.register_protocol(
              PROTO_NAME,
              true,
              FcgInboundHandler::InboundProtocolHandlerFactory.new())
          end
        end
      end
    end
  end
end

