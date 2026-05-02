module Baykit
  module BayServer
    module Agent
      module Letters
        class AcceptedLetter < Letter
          attr :client_rudder

          def initialize(rd, mpx, client_rd)
            super(rd, mpx)
            @client_rudder = client_rd
          end
        end
      end
    end
  end
end

