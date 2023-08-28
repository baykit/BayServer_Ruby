#
#  AJP Protocol
#  https://tomcat.apache.org/connectors-doc/ajp/ajpv13a.html
#
module Baykit
  module BayServer
    module Docker
      module Ajp
        class AjpCommand < Baykit::BayServer::Protocol::Command

          attr_accessor :to_server

          def initialize(type, to_server)
            super type
            @to_server = to_server
          end

          def unpack(pkt)
            if pkt.type() != @type
              raise RuntimeError.new("Illegal State")
            end
            @to_server = pkt.to_server
          end

          #
          # Super class method must be called from last line of override method 
          # since header cannot be packed before data is constructed.
          # 
          def pack(pkt)
            if pkt.type() != @type
              raise RuntimeError.new "Illegal State"
            end
            pkt.to_server = @to_server
            pack_header(pkt)
          end

          def pack_header(pkt) 
            acc = pkt.new_ajp_header_accessor
            if pkt.to_server
              acc.put_byte(0x12)
              acc.put_byte(0x34)
            else
              acc.put_byte('A')
              acc.put_byte('B')
            end

            acc.put_byte((pkt.data_len >> 8) & 0xff)
            acc.put_byte(pkt.data_len & 0xff)
          end
        end
      end
    end
  end
end

