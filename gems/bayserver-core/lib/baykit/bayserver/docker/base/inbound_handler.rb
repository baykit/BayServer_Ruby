module Baykit
  module BayServer
    module Docker
      module Base
        module InboundHandler  # interface

          #
          #  Send protocol error
          #   return true if connection must be closed
          #
          def send_req_protocol_error(protocol_ex)
            raise NotImplementedError()
          end

          #
          #  Send HTTP headers to client
          #
          def send_res_headers(tur)
            raise NotImplementedError()
          end

          #
          # Send Contents to client
          #
          def send_res_content(tur, bytes, ofs, len, &callback)
            raise NotImplementedError()
          end

          #
          # Send end of contents to client.
          #  sendEnd cannot refer Tour instance because it is discarded before call.
          #
          def send_end_tour(tur, keep_alive, &callback)
            raise NotImplementedError()
          end

        end
      end
    end
  end
end

