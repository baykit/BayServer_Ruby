
module Baykit
  module BayServer
    module Rudders
      module Rudder # interface

        def key
          raise NotImplementedError.new
        end

        def set_non_blocking
          raise NotImplementedError.new
        end

        def read(buf, len)
          raise NotImplementedError.new
        end

        def write(buf)
          raise NotImplementedError.new
        end

        def close
          raise NotImplementedError.new
        end
      end
    end
  end
end