

module Baykit
  module BayServer
    module Common
      module Multiplexer # interface

        def add_rudder_state(rd, st)
          raise NotImplementedError.new
        end

        def get_rudder_state(rd)
          raise NotImplementedError.new
        end

        def get_transporter(rd)
          raise NotImplementedError.new
        end

        def req_accept(rd)
          raise NotImplementedError.new
        end

        def req_connect(rd, adr)
          raise NotImplementedError.new
        end

        def req_read(rd)
          raise NotImplementedError.new
        end

        def req_write(rd, buf, adr, tag, lis)
          raise NotImplementedError.new
        end

        def req_end(rd)
          raise NotImplementedError.new
        end

        def req_close(rd)

        end

        def cancel_read(st)
          raise NotImplementedError.new
        end

        def cancel_write(st)
          raise NotImplementedError.new
        end

        def next_accept(st)
          raise NotImplementedError.new
        end

        def next_read(st)
          raise NotImplementedError.new
        end

        def next_write(st)
          raise NotImplementedError.new
        end

        def shutdown()
          raise NotImplementedError.new
        end

        def is_non_blocking()
          raise NotImplementedError.new
        end

        def use_async_api()
          raise NotImplementedError.new
        end

        def consume_oldest_unit(st)
          raise NotImplementedError.new
        end

        def close_rudder(st)
          raise NotImplementedError.new
        end

        def is_busy
          raise NotImplementedError.new
        end

        def on_busy
          raise NotImplementedError.new
        end

        def on_free
          raise NotImplementedError.new
        end
      end
    end
  end
end
