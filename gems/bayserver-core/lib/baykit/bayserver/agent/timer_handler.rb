
module Baykit
  module BayServer
    module Agent
      module TimerHandler # interface

        def on_timer()
          raise NotImplementedError.new
        end

      end
    end
  end
end

