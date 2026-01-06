module Baykit
  module BayServer
    module Agent
      module Letters
        class WroteLetter < Letter
          attr :n_bytes

          def initialize(state_id, rd, mpx, n)
            super state_id, rd, mpx
            @n_bytes = n
          end
        end
      end
    end
  end
end

