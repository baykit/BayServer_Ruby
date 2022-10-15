require 'baykit/bayserver/protocol/packet_factory'

module Baykit
  module BayServer
    module Docker
      module Ajp
        class AjpPacketFactory < Baykit::BayServer::Protocol::PacketFactory

          def create_packet(type)
            AjpPacket.new(type)
          end

        end
      end
    end
  end
end

