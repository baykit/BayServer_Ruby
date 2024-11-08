module Baykit
  module BayServer
    module Agent
      module Transporter
        module DataListener  # interface

          def notify_connect()
            raise NotImplementedError.new
          end

          def notify_handshake_done(protocol)
            raise NotImplementedError.new
          end

          def notify_read(buf)
            raise NotImplementedError.new
          end

          def notify_eof()
            raise NotImplementedError.new
          end

          def notify_protocol_error(err)
            raise NotImplementedError.new
          end

          def notify_close()
            raise NotImplementedError.new
          end

          def check_timeout(duration_sec)
            raise NotImplementedError.new
          end
        end
      end
    end
  end
end
