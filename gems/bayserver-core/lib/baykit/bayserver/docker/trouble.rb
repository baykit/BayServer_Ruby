require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Trouble
        include Docker # implements

        TROUBLE_METHOD_GUIDE = 1
        TROUBLE_METHOD_TEXT = 2
        TROUBLE_METHOD_REROUTE = 3

        class Command
          attr :method
          attr :target

          def initialize(method, target)
            @method = method
            @target = target
          end
        end

        def find(status) Command
          raise NotImplementedError.new
        end
      end
    end
  end
end
