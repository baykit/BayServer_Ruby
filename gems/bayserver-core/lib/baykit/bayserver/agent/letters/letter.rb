module Baykit
  module BayServer
    module Agent
      module Letters
        class Letter
          attr :state
          def initialize(st)
            @state = st
          end
        end
      end
    end
  end
end

