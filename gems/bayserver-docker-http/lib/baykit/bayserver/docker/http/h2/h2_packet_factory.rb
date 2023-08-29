require 'baykit/bayserver/protocol/packet_factory'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2PacketFactory <Baykit::BayServer::Protocol::PacketFactory

            def create_packet(type)
              H2Packet.new(type)
            end

          end
        end
      end
    end
  end
end


