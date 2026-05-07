module Baykit
  module BayServer
    module Agent
      module Letters
        class ErrorLetter < Letter
          attr_accessor :err

          def init(rd, mpx, err)
            super(rd, mpx)
            @err = err
          end

          def reset
            super
            @err = nil
          end
        end
      end
    end
  end
end
