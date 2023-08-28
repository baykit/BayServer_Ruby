require 'baykit/bayserver/protocol/packet'

#
#  FCGI spec
#    http://www.mit.edu/~yandros/doc/specs/fcgi-spec.html
#    
#  FCGI Packet (Record) format
#          typedef struct {
#              unsigned char version;
#              unsigned char type;
#              unsigned char requestIdB1;
#              unsigned char requestIdB0;
#              unsigned char contentLengthB1;
#              unsigned char contentLengthB0;
#              unsigned char paddingLength;
#              unsigned char reserved;
#              unsigned char contentData[contentLength];
#              unsigned char paddingData[paddingLength];
#          } FCGI_Record;
#
module Baykit
  module BayServer
    module Docker
      module Fcgi
        class FcgPacket < Baykit::BayServer::Protocol::Packet

          PREAMBLE_SIZE = 8

          VERSION = 1
          MAXLEN = 65535

          FCGI_NULL_REQUEST_ID = 0

          attr :version
          attr_accessor :req_id

          def initialize(type)
            super(type, PREAMBLE_SIZE, MAXLEN)
            @version = VERSION
          end

          def reset()
            super
            @version = VERSION
            @req_id = 0
          end

          def to_s
            "FcgPacket(#{@type}) id=#{@req_id}"
          end
        end
      end
    end
  end
end

