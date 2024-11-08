module Baykit
  module BayServer
    module Docker
      module Docker # interface

        def init(ini, parent)
          raise NotImplementedError.new
        end

        def type()
          raise NotImplementedError.new
        end
      end
    end
  end
end