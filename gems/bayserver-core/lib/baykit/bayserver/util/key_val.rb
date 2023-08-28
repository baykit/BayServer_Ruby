module Baykit
  module BayServer
    module Util
      class KeyVal
        attr :name
        attr :value

        def initialize(name, val)
          @name = name
          @value = val
        end
      end
    end
  end
end
