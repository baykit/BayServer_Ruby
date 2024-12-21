require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Agent
      module Multiplexer
        module Transporter # interface
          include Baykit::BayServer::Util::Reusable # implements

          def init()
            raise NotImplementedError.new
          end

          def on_connected(rd)
            raise NotImplementedError.new
          end

          def on_read(rd, data, adr)
            raise NotImplementedError.new
          end

          def on_error(rd, e)
            raise NotImplementedError.new
          end

          def on_closed(rd)
            raise NotImplementedError.new
          end

          def req_connect(rd, adr)
            raise NotImplementedError.new
          end

          def req_read(rd)
            raise NotImplementedError.new
          end

          def req_write(rd, buf, adr, tag, &lis)
            raise NotImplementedError.new
          end

          def req_close(rd)
            raise NotImplementedError.new
          end

          def check_timeout(rd, duretion_sec)
            raise NotImplementedError.new
          end

          def get_read_buffer_size
            raise NotImplementedError.new
          end

          def print_usage(indent)
            raise NotImplementedError.new
          end
        end
      end
    end
  end
end