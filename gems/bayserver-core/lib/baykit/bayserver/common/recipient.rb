

module Baykit
  module BayServer
    module Common
      module Recipient # interface

        #
        # Receive letters
        #
        def receive(wait)
          raise NotImplementedError.new
        end

        #
        # Wake up the recipient
        #
        def wakeup()
          raise NotImplementedError.new
        end
      end
    end
  end
end
