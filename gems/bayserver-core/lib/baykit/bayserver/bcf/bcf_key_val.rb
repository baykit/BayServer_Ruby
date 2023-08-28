require 'baykit/bayserver/bcf/package'

module Baykit
  module BayServer
    module Bcf

      class BcfKeyVal < BcfObject
        attr :key
        attr :value

        def initialize(key, val, file_name, line_no)
          super file_name, line_no
          @key = key
          @value = val
        end
      end
    end
  end
end
