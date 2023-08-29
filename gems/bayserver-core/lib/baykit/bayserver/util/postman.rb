
module Baykit
  module BayServer
    module Util
        module Postman # interface

          def post(buf, adr, tag, lis)
            raise NotImplementedError.new()
          end

          def flush()
            raise NotImplementedError.new()
          end

          def post_end()
            raise NotImplementedError.new()
          end

          def is_zombie()
            raise NotImplementedError.new()
          end

          def abort()
            raise NotImplementedError.new()
          end

          def open_valve()
            raise NotImplementedError.new()
          end

        end
    end
  end
end

