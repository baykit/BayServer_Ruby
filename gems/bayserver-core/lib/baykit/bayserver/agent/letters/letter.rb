module Baykit
  module BayServer
    module Agent
      module Letters
        class Letter
          attr :state_id
          attr :rudder
          attr :multiplexer
          def initialize(state_id, rd, mpx)
            @state_id = state_id
            @rudder = rd
            @multiplexer = mpx
          end
        end
      end
    end
  end
end

