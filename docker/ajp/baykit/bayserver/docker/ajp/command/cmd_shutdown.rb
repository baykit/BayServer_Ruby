require 'baykit/bayserver/docker/ajp/ajp_command'
require 'baykit/bayserver/docker/ajp/ajp_type'

#
#  Shutdown command format
# 
#    none
#
module Baykit
  module BayServer
    module Docker
      module Ajp
        module Command
          class CmdShutdown < Baykit::BayServer::Docker::Ajp::AjpCommand

            def initialize
              super(AjpType::SHUTDOWN, true)
            end

            def unpack(pkt)
              super
            end

            def pack(pkt)
              super
            end

            def handle(handler)
              return handler.handle_shutdown(self)
            end
          end
        end
      end
    end
  end
end

