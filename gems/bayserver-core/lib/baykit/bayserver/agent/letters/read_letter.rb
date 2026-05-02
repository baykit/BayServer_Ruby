module Baykit
  module BayServer
    module Agent
      module Letters
        class ReadLetter < Letter

          attr :n_bytes
          attr :address

          def initialize(rd, mpx, n, adr = "")
            super rd, mpx
            @n_bytes = n
            @address = adr
          end
        end
      end
    end
  end
end

