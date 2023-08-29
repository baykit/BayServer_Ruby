require 'baykit/bayserver/protocol/packet'

module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          class H1Packet < Baykit::BayServer::Protocol::Packet

            MAX_HEADER_LEN = 0 # H1 packet does not have packet header
            MAX_DATA_LEN = 65536


            def initialize(type)
              super type, MAX_HEADER_LEN, MAX_DATA_LEN
            end

            def to_s
              "H1Packet(#{@type}) len=#{data_len()}"
            end
          end
        end
      end
    end
  end
end


