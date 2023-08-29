require 'baykit/bayserver/docker/http/h1/h1_command'

module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          module Command

            #
            #  Dummy packet (empty packet) to notify contents are sent
            #
            class CmdEndContent < Baykit::BayServer::Docker::Http::H1::H1Command


              def initialize()
                super(H1Type::END_CONTENT)
              end

              def unpack(pkt)
              end

              def pack(pkt)
              end

              def handle(cmd_handler)
                return cmd_handler.handle_end_content(self)
              end
            end
          end
        end
      end
    end
  end
end


