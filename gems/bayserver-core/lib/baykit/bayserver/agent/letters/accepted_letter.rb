module Baykit
  module BayServer
    module Agent
      module Letters
        class AcceptedLetter < Letter
          attr :client_rudder

          def initialize(state_id, rd, mpx, client_rd)
            super(state_id, rd, mpx)
            @client_rudder = client_rd
          end
        end
      end
    end
  end
end

