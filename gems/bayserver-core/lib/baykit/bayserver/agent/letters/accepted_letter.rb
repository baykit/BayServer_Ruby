module Baykit
  module BayServer
    module Agent
      module Letters
        class AcceptedLetter < Letter
          attr_accessor :client_rudder

          def init(rd, mpx, client_rd)
            super(rd, mpx)
            @client_rudder = client_rd
          end

          def reset
            super
            @client_rudder = nil
          end
        end
      end
    end
  end
end
