module Baykit
  module BayServer
    module Agent
      module Letters
        class ErrorLetter < Letter
          attr :err
          def initialize(rd, mpx, err)
            super rd, mpx
            @err = err
          end
        end
      end
    end
  end
end

