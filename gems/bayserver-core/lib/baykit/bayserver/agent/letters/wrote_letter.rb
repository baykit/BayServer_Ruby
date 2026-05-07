module Baykit
  module BayServer
    module Agent
      module Letters
        class WroteLetter < Letter
          attr_accessor :n_bytes

          def init(rd, mpx, n)
            super(rd, mpx)
            @n_bytes = n
          end

          def reset
            super
            @n_bytes = 0
          end
        end
      end
    end
  end
end
