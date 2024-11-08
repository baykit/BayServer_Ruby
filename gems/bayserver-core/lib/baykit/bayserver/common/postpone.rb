

module Baykit
  module BayServer
    module Common
      module Postpone # interface

        def run()
          raise NotImplementedError.new
        end

      end
    end
  end
end
