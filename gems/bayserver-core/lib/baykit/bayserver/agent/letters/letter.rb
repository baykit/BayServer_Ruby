module Baykit
  module BayServer
    module Agent
      module Letters
        class Letter
          attr :rudder
          attr :multiplexer
          def initialize(rd, mpx)
            @rudder = rd
            @multiplexer = mpx
          end
        end
      end
    end
  end
end

