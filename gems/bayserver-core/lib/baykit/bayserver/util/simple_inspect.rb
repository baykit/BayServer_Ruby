
module Baykit
  module BayServer
    module Util
      module SimpleInspect
        def inspect
          self.class.to_s + "::" + object_id
        end
      end
    end
  end
end
