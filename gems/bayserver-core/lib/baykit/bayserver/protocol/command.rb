module Baykit
  module BayServer
    module Protocol
      class Command

        # abstract methods
        #
        # unpack(P packet)
        # pack(P packet)
        # handle(H handler)

        attr :type

        def initialize(type)
          @type = type
        end

      end
    end
  end
end
