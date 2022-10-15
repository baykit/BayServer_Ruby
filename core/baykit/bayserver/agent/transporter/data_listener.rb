module Baykit
  module BayServer
    module Agent
      module Transporter
        module DataListener  # interface

          def notify_connect()
            raise NotImplementedError()
          end

          def notify_handshake_done(protocol)
            raise NotImplementedError()
          end

          def notify_read(buf)
            raise NotImplementedError()
          end

          def notify_eof()
            raise NotImplementedError()
          end

          def notify_protocol_error(err)
            raise NotImplementedError()
          end

          def notify_close()
            raise NotImplementedError()
          end

          def check_timeout(duration_sec)
            raise NotImplementedError()
          end
        end
      end
    end
  end
end
