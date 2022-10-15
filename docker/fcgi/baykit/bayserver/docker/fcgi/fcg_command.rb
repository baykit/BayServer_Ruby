module Baykit
  module BayServer
    module Docker
      module Fcgi
        class FcgCommand < Baykit::BayServer::Protocol::Command

          attr :req_id

          def initialize(type, req_id)
            super(type)
            @req_id = req_id
          end

          def unpack(pkt)
            @req_id = pkt.req_id
          end

          #
          # Super class method must be called from last line of override method 
          # since header cannot be packed before data is constructed
          #
          def pack(pkt)
            pkt.req_id = @req_id
            pack_header(pkt)
          end

          def pack_header(pkt)
            acc = pkt.new_header_accessor()
            acc.put_byte(pkt.version)
            acc.put_byte(pkt.type)
            acc.put_short(pkt.req_id)
            acc.put_short(pkt.data_len)
            acc.put_byte(0)  # paddinglen
            acc.put_byte(0)  # reserved
          end
        end
      end
    end
  end
end
