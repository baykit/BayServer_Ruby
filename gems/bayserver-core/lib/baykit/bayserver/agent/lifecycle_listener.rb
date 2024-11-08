
module Baykit
  module BayServer
    module Agent
      module LifecycleListener # interface

        def add(agent_id)
          raise NotImplementedError
        end

        def remove(agent_id)
          raise NotImplementedError
        end
      end
    end
  end
end

