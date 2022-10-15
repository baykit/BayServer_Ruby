require 'baykit/bayserver/protocol/packet_factory'

module Baykit
  module BayServer
    module Docker
      module Fcgi
        class FcgPacketFactory < Baykit::BayServer::Protocol::PacketFactory

          def create_packet(type)
            FcgPacket.new(type)
          end

        end
      end
    end
  end
end
