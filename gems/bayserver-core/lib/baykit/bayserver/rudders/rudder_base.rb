
module Baykit
  module BayServer
    module Rudders
      class RudderBase
        include Rudder # implements

        attr :closed

        def close
          @closed = true
        end

        def closed?
          return @closed
        end

      end
    end
  end
end