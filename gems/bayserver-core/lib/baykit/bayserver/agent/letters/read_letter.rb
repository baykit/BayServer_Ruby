module Baykit
  module BayServer
    module Agent
      module Letters
        class ReadLetter < Letter
          attr_accessor :n_bytes
          attr_accessor :address

          def init(rd, mpx, n, adr = "")
            super(rd, mpx)
            @n_bytes = n
            @address = adr
          end

          def reset
            super
            @n_bytes = 0
            @address = nil
          end
        end
      end
    end
  end
end
