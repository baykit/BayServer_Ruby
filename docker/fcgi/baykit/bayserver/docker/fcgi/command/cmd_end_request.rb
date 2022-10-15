require 'baykit/bayserver/docker/fcgi/fcg_command'
require 'baykit/bayserver/docker/fcgi/fcg_type'

#
#  FCGI spec
#    http://www.mit.edu/~yandros/doc/specs/fcgi-spec.html
# 
#  Endrequest command format
#          typedef struct {
#              unsigned char appStatusB3;
#              unsigned char appStatusB2;
#              unsigned char appStatusB1;
#              unsigned char appStatusB0;
#              unsigned char protocolStatus;
#              unsigned char reserved[3];
#          } FCGI_EndRequestBody;
#
module Baykit
  module BayServer
    module Docker
      module Fcgi
        module Command
          class CmdEndRequest < Baykit::BayServer::Docker::Fcgi::FcgCommand

            FCGI_REQUEST_COMPLETE = 0
            FCGI_CANT_MPX_CONN = 1
            FCGI_OVERLOADED = 2
            FCGI_UNKNOWN_ROLE = 3

            attr :app_status
            attr :protocol_status

            def initialize(req_id)
              super(FcgType::END_REQUEST, req_id)
              @app_status = 0
              @protocol_status = FCGI_REQUEST_COMPLETE
            end

            def unpack(pkt)
              super
              acc = pkt.new_data_accessor
              @app_status = acc.get_int
              @protocol_status = acc.get_byte
            end

            def pack(pkt)
              acc = pkt.new_data_accessor
              acc.put_int(@app_status)
              acc.put_byte(@protocol_status)
              reserved = " " * 3
              acc.put_bytes(reserved)

              # must be called from last line
              super
            end

            def handle(cmd_handler)
              return cmd_handler.handle_end_request(self)
            end

          end
        end
      end
    end
  end
end