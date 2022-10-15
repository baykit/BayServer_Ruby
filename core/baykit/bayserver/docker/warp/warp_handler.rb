module Baykit
  module BayServer
    module Docker
      module Warp
        module WarpHandler # interface

          def next_warp_id()
            raise NotImplementedError()
          end

          def new_warp_data(warp_id)
            raise NotImplementedError()
          end

          def post_warp_headers(tur)
            raise NotImplementedError()
          end

          def post_warp_contents(tur, buf, start, len, &callback)
            raise NotImplementedError()
          end

          def post_warp_end(tur)
            raise NotImplementedError()
          end

          #
          # Verify if protocol is allowed
          #
          def verify_protocol(protocol)
            raise NotImplementedError()
          end

        end
      end
    end
  end
end
