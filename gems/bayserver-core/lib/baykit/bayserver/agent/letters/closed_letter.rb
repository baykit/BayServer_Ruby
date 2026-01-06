module Baykit
  module BayServer
    module Agent
      module Letters
        class ClosedLetter < Letter
          def initialize(state_id, rd, mpx)
            super state_id, rd, mpx
          end
        end
      end
    end
  end
end

