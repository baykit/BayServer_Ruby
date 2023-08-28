require 'baykit/bayserver/docker/http/h2/package'

#
# HTTP/2 RstStream payload format
#
#  +---------------------------------------------------------------+
#  |                        Error Code (32)                        |
#  +---------------------------------------------------------------+
#
#
module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module Command

            class CmdRstStream < Baykit::BayServer::Docker::Http::H2::H2Command
              include Baykit::BayServer::Docker::Http::H2

              attr :error_code

              def initialize(stream_id, flags=nil)
                super(H2Type::RST_STREAM, stream_id, flags)
             end

              def unpack(pkt)
                super
                acc = pkt.new_data_accessor
                @error_code = acc.get_int
              end

              def pack(pkt)
                acc = pkt.new_data_accessor
                acc.put_int(@error_code)
                super
              end

              def handle(cmd_handler)
                return cmd_handler.handle_rst_stream(self)
              end
            end
          end
        end
      end
    end
  end
end


