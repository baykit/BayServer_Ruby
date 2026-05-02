module Baykit
  module BayServer
    module Agent
      module Letters
        class WroteLetter < Letter
          attr :n_bytes

          def initialize(rd, mpx, n)
            super rd, mpx
            @n_bytes = n
          end
        end
      end
    end
  end
end

