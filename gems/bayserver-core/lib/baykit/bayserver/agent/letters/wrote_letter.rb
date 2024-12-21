module Baykit
  module BayServer
    module Agent
      module Letters
        class WroteLetter < Letter
          attr :n_bytes

          def initialize(st, n)
            super st
            @n_bytes = n
          end
        end
      end
    end
  end
end

