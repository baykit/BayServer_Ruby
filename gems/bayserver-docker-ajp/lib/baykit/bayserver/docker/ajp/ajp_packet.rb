require 'baykit/bayserver/protocol/packet_part_accessor'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/protocol/packet'

#
#  AJP Protocol
#  https://tomcat.apache.org/connectors-doc/ajp/ajpv13a.html
# 
#  AJP packet spec
# 
#    packet:  preamble, length, body
#    preamble:
#         0x12, 0x34  (client->server)
#      | 'A', 'B'     (server->client)
#    length:
#       2 byte
#    body:
#       $length byte
# 
# 
#   Body format
#     client->server
#     Code     Type of Packet    Meaning
#        2     Forward Request   Begin the request-processing cycle with the following data
#        7     Shutdown          The web server asks the container to shut itself down.
#        8     Ping              The web server asks the container to take control (secure login phase).
#       10     CPing             The web server asks the container to respond quickly with a CPong.
#     none     Data              Size (2 bytes) and corresponding body data.
# 
#     server->client
#     Code     Type of Packet    Meaning
#        3     Send Body Chunk   Send a chunk of the body from the servlet container to the web server (and presumably, onto the browser).
#        4     Send Headers      Send the response headers from the servlet container to the web server (and presumably, onto the browser).
#        5     End Response      Marks the end of the response (and thus the request-handling cycle).
#        6     Get Body Chunk    Get further data from the request if it hasn't all been transferred yet.
#        9     CPong Reply       The reply to a CPing request
# 
#

module Baykit
  module BayServer
    module Docker
      module Ajp
        class AjpPacket < Baykit::BayServer::Protocol::Packet
          class AjpAccessor < Baykit::BayServer::Protocol::PacketPartAccessor
            include Baykit::BayServer::Util

            def initialize(type, start, max_len)
              super
            end

            def put_string(str)
              if StringUtil.empty?(str)
                put_short(0xffff)
              else
                put_short(str.length)
                super str
                put_byte(0) # null terminator
              end
            end

            def get_string
              get_string_by_len(get_short())
            end

            def get_string_by_len(len)

              if len == 0xffff
                return ""
              end

              buf = StringUtil.alloc(len)
              get_bytes(buf, 0, len)
              get_byte() # null terminator

              buf
            end
          end

          PREAMBLE_SIZE = 4
          MAX_DATA_LEN = 8192 - PREAMBLE_SIZE
          MIN_BUF_SIZE = 1024

          attr_accessor :to_server

          def initialize(type)
            super(type, PREAMBLE_SIZE, MAX_DATA_LEN)
          end

          def reset()
            @to_server = false
            super
          end

          def new_ajp_header_accessor
            AjpAccessor.new(self, 0, PREAMBLE_SIZE)
          end

          def new_ajp_data_accessor
            AjpAccessor.new(self, PREAMBLE_SIZE, -1)
          end

          def to_s
            "AjpPacket(#{@type})"
          end

        end
      end
    end
  end
end

