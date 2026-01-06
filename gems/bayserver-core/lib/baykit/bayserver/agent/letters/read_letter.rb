module Baykit
  module BayServer
    module Agent
      module Letters
        class ReadLetter < Letter

          attr :n_bytes
          attr :address

          def initialize(state_id, rd, mpx, n, adr = "")
            super state_id, rd, mpx
            @n_bytes = n
            @address = adr
          end
        end
      end
    end
  end
end

