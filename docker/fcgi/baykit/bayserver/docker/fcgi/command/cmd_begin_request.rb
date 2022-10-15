require 'baykit/bayserver/docker/fcgi/fcg_command'
require 'baykit/bayserver/docker/fcgi/fcg_type'

#
#  FCGI spec
#    http://www.mit.edu/~yandros/doc/specs/fcgi-spec.html
# 
#  Begin request command format
#          typedef struct {
#              unsigned char roleB1;
#              unsigned char roleB0;
#              unsigned char flags;
#              unsigned char reserved[5];
#          } FCGI_BeginRequestBody;
#
module Baykit
  module BayServer
    module Docker
      module Fcgi
        module Command
          class CmdBeginRequest < Baykit::BayServer::Docker::Fcgi::FcgCommand
            include Baykit::BayServer::Docker::Fcgi

            FCGI_KEEP_CONN = 1
            FCGI_RESPONDER = 1
            FCGI_AUTHORIZER = 2
            FCGI_FILTER = 3

            attr_accessor :role
            attr_accessor :keep_conn

            def initialize(req_id)
              super(FcgType::BEGIN_REQUEST, req_id)
            end

            def unpack(pkt)
              super

              acc = pkt.new_data_accessor
              @role = acc.get_short
              flags = acc.get_byte
              @keep_conn = (flags & FCGI_KEEP_CONN) != 0
            end

            def pack(pkt)
              acc = pkt.new_data_accessor
              acc.put_short(@role)
              acc.put_byte(@keep_conn ? 1 : 0)
              reserved = " " * 5
              acc.put_bytes(reserved)

              # must be called from last line
              super
            end

            def handle(cmd_handler)
              return cmd_handler.handle_begin_request(self)
            end

          end
        end
      end
    end
  end
end

