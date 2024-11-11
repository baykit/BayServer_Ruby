

module Baykit
  module BayServer
    module Common
      class Vehicle # abstract class

        attr :id

        def initialize(id)
          @id = id
        end
        def run()
          raise NotImplementedError.new
        end

        def on_timer()
          raise NotImplementedError.new
        end

      end
    end
  end
end
