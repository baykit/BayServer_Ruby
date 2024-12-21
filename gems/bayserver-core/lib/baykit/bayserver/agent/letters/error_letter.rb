module Baykit
  module BayServer
    module Agent
      module Letters
        class ErrorLetter < Letter
          attr :err
          def initialize(st, err)
            super st
            @err = err
          end
        end
      end
    end
  end
end

