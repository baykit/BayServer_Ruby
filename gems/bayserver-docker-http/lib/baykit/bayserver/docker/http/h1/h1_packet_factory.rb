require 'baykit/bayserver/protocol/packet_factory'

module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          class H1PacketFactory < Baykit::BayServer::Protocol::PacketFactory

            def create_packet(type)
              H1Packet.new(type)
            end

          end
        end
      end
    end
  end
end


