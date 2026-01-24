require 'baykit/bayserver/util/selector'

module Baykit
  module BayServer
    module Util

      class RbSelector < Selector

        def initialize
          super
        end

        def select(timeout_sec = nil)
          if timeout_sec == nil
            timeout_sec = 0
          end
          except_list = []

          read_list = []
          write_list = []
          @lock.synchronize do
            @io_op_map.keys().each do |io|
              if (@io_op_map[io] & OP_READ) != 0
                read_list << io
              end
              if (@io_op_map[io] & OP_WRITE) != 0
                write_list << io
              end
            end
          end
          #BayLog.debug("Select read_list=%s", read_list)
          #BayLog.debug("Select write_list=%s", write_list)
          selected_read_list, selected_write_list = Kernel.select(read_list, write_list, except_list, timeout_sec)

          result = {}
          if selected_read_list != nil
            selected_read_list.each do |io|
              register_read(io, result)
            end
          end

          if selected_write_list != nil
            selected_write_list.each do |io|
              register_write(io, result)
            end
          end

          return result
        end

      end
    end
  end
end

