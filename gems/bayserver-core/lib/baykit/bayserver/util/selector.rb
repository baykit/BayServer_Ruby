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
          @lock.synchronize do
            return @io_op_map.length
          end
        end

        def select(timeout_sec = nil)
          raise NotImplementedError
        end

        def validate_channel(ch)
          unless ch.is_a?(IO) || (defined?(OpenSSL::SSL::SSLSocket) && ch.is_a?(OpenSSL::SSL::SSLSocket))
            raise ArgumentError
          end
        end

        private
        def register_read(io, io_op)
          @lock.synchronize do
            if io_op.key?(io)
              io_op[io] = (io_op[io] | OP_READ)
            else
              io_op[io] = OP_READ
            end
          end
        end

        def register_write(io, io_op)
          @lock.synchronize do
            if io_op.key?(io)
              io_op[io] = (io_op[io] | OP_WRITE)
            else
              io_op[io] = OP_WRITE
            end
          end
        end

        def unregister_read(io, io_op)
          @lock.synchronize do
            if io_op.include?(io)
              if io_op[io] == OP_READ
                io_op.delete(io)
              else
                io_op[io] = OP_WRITE
              end
            end
          end
        end


        def unregister_write(io, io_op)
          @lock.synchronize do
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
end

