require 'baykit/bayserver/docker/ajp/ajp_command'
require 'baykit/bayserver/docker/ajp/ajp_type'
require 'baykit/bayserver/docker/ajp/ajp_packet'

#
# Get Body Chunk format
#
# AJP13_GET_BODY_CHUNK :=
#   prefix_code       6
#   requested_length  (integer)
#
module Baykit
  module BayServer
    module Docker
      module Ajp
        module Command
          class CmdGetBodyChunk < Baykit::BayServer::Docker::Ajp::AjpCommand
            attr_accessor :req_len

            def initialize()
              super AjpType::GET_BODY_CHUNK, false
            end

            def pack(pkt)
              acc = pkt.new_ajp_data_accessor()
              acc.put_byte(@type)
              acc.put_short(@req_len)

              # must be called from last line
              super
            end

            def handle(handler)
              return handler.handle_get_body_chunk(self)
            end


          end
        end
      end
    end
  end
end

