module Baykit
  module BayServer
    module Agent
      module Letters
        class ErrorLetter < Letter
          attr :err
          def initialize(state_id, rd, mpx, err)
            super state_id, rd, mpx
            @err = err
          end
        end
      end
    end
  end
end

