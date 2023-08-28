require 'baykit/bayserver/docker/ajp/ajp_command'
require 'baykit/bayserver/docker/ajp/ajp_type'

#
#  End response body format
# 
#  AJP13_END_RESPONSE :=
#    prefix_code       5
#    reuse             (boolean)
#
module Baykit
  module BayServer
    module Docker
      module Ajp
        module Command
          class CmdEndResponse < Baykit::BayServer::Docker::Ajp::AjpCommand
            attr_accessor :reuse

            def initialize
              super(AjpType::END_RESPONSE, false)
            end

            def pack(pkt)
              acc = pkt.new_ajp_data_accessor
              acc.put_byte(@type)
              acc.put_byte(@reuse ? 1 : 0)

              #  must be called from last line
              super
            end

            def unpack(pkt)
              super
              acc = pkt.new_ajp_data_accessor()
              acc.get_byte()   # prefix code
              @reuse = acc.get_byte() != 0
            end

            def handle(handler)
              return handler.handle_end_response(self)
            end
          end
        end
      end
    end
  end
end

