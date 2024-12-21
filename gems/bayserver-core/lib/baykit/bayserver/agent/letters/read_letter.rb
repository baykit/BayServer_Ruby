module Baykit
  module BayServer
    module Agent
      module Letters
        class ReadLetter < Letter

          attr :n_bytes
          attr :address

          def initialize(st, n, adr = "")
            super st
            @n_bytes = n
            @address = adr
          end
        end
      end
    end
  end
end

