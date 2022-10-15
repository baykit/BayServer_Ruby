require 'baykit/bayserver/protocol/command'

module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          class H1Command < Baykit::BayServer::Protocol::Command
            def initialize(type)
              super
            end
          end
        end
      end
    end
  end
end


