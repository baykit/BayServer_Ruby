require "nio"
require "thread"
require 'baykit/bayserver/util/selector'

module Baykit
  module BayServer
    module Util
      class NioSelector < Selector

        attr :selector
        attr :io_monitor_map

        def initialize
          super

          @selector = NIO::Selector.new
          @io_monitor_map = {}      # io -> monitor(:r)
        end
        def select(timeout_sec=nil)
          timeout_sec = 0 if timeout_sec.nil?
          ready_mon_list = @selector.select(timeout_sec)

          result = {}
          if ready_mon_list
            ready_mon_list.each do |mon|
              io = mon.io
              if mon.readable?
                register_read(io, result)
              end
              if mon.writable?
                register_write(io, result)
              end
            end
          end
          result
        end

        def count
          @lock.synchronize { @ops.length }
        end

        private
        def register_read(io, io_op)

          if !@io_op_map.key?(io)
            @io_monitor_map[io] = @selector.register(io, :r)
          else
            op = @io_op_map[io]
            if op & OP_WRITE != 0
              @io_monitor_map[io].interests = :rw
            end
          end

          super  # Update @io_monitor_map
        end

        def register_write(io, io_op)

          if !@io_op_map.key?(io)
            @io_monitor_map[io] = @selector.register(io, :w)
          else
            op = @io_op_map[io]
            if op & OP_READ != 0
              @io_monitor_map[io].interests = :rw
            end
          end

          super  # Update @io_monitor_map
        end

        def unregister_read(io, io_op)

          if @io_op_map.key?(io)
            op = @io_op_map[io]
            if op & OP_WRITE != 0
              @io_monitor_map[io].interests = :w
            else
              @selector.deregister(io)
            end
          end

          super  # Update @io_monitor_map
        end


        def unregister_write(io, io_op)

          if @io_op_map.key?(io)
            op = @io_op_map[io]
            if op & OP_READ != 0
              @io_monitor_map[io].interests = :r
            else
              @selector.deregister(io)
            end
          end

          super  # Update @io_monitor_map
        end

      end
    end
  end
end
