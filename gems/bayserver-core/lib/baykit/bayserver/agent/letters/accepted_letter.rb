module Baykit
  module BayServer
    module Agent
      module Letters
        class AcceptedLetter < Letter
          attr :client_rudder

          def initialize(st, client_rd)
            super(st)
            @client_rudder = client_rd
          end
        end
      end
    end
  end
end

