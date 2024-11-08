module Baykit
  module BayServer
    module Agent
      class Letter
        ACCEPTED = 1
        CONNECTED = 2
        READ = 3
        WROTE = 4
        CLOSEREQ = 5

        attr :type
        attr :state
        attr :n_bytes
        attr :address
        attr :err
        attr :client_rudder

        def initialize(type, st, client_rd, n, adr, err)
          @type = type
          @state = st
          @client_rudder = client_rd
          @n_bytes = n
          @err = err
        end

      end
    end
  end
end

