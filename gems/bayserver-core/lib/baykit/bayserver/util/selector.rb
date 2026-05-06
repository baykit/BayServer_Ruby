module Baykit
  module BayServer
    module Util

      #
      # Like Selector class of Python
      #
      class Selector
        OP_READ = 1
        OP_WRITE = 2

        attr :io_op_map
        attr :lock

        def initialize
          @io_op_map = {}
          @lock = Mutex.new()
        end

        def register(ch, op)
          validate_channel(ch)
          if op & OP_READ != 0
            register_read(ch, @io_op_map)
          end
          if op & OP_WRITE != 0
            register_write(ch, @io_op_map)
          end
        end

        def unregister(ch)
          validate_channel(ch)
          unregister_read(ch, @io_op_map)
          unregister_write(ch, @io_op_map)
        end

        def modify(ch, op)
          validate_channel(ch)
          if op & OP_READ != 0
            register_read(ch, @io_op_map)
          else
            unregister_read(ch, @io_op_map)
          end

          if op & OP_WRITE != 0
            register_write(ch, @io_op_map)
          else
            unregister_write(ch, @io_op_map)
          end
        end

        def get_op(ch)
          validate_channel(ch)
          return @io_op_map[ch]
        end

        def count
          return @io_op_map.length
        end

        def select(timeout_sec = nil)
          raise NotImplementedError
        end

        def validate_channel(ch)
          unless ch.is_a?(IO) || (defined?(OpenSSL::SSL::SSLSocket) && ch.is_a?(OpenSSL::SSL::SSLSocket))
            raise ArgumentError
          end
        end

        # Each Selector instance is owned by one SpiderMultiplexer / one
        # GrandAgent and only touched from that agent's event-loop thread
        # -- there is no other thread mutating @io_op_map. The previous
        # @lock.synchronize on every register / unregister was pure
        # overhead in the per-request hot path. The lock attribute
        # remains for ABI compatibility with any external caller, but
        # the body here no longer pays for it.
        private
        def register_read(io, io_op)
          if io_op.key?(io)
            io_op[io] = (io_op[io] | OP_READ)
          else
            io_op[io] = OP_READ
          end
        end

        def register_write(io, io_op)
          if io_op.key?(io)
            io_op[io] = (io_op[io] | OP_WRITE)
          else
            io_op[io] = OP_WRITE
          end
        end

        def unregister_read(io, io_op)
          if io_op.include?(io)
            if io_op[io] == OP_READ
              io_op.delete(io)
            else
              io_op[io] = OP_WRITE
            end
          end
        end


        def unregister_write(io, io_op)
          if io_op.include?(io)
            if io_op[io] == OP_WRITE
              io_op.delete(io)
            else
              io_op[io] = OP_READ
            end
          end
        end


      end
    end
  end
end

