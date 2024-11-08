module Baykit
  module BayServer
    module Util

      #
      # Like Selector class of Python
      #
      class Selector
        OP_READ = 1
        OP_WRITE = 2

        attr :channels
        attr :lock

        def initialize
          @channels = {}
          @lock = Mutex.new()
        end

        def register(ch, op)
          #BayLog.debug("register io=%s", ch)
          if not ((ch.kind_of? IO) || (ch.kind_of? OpenSSL::SSL::SSLSocket))
            raise ArgumentError
          end
          if op & OP_READ != 0
            register_read(ch, @channels)
          end
          if op & OP_WRITE != 0
            register_write(ch, @channels)
          end
        end

        def unregister(ch)
          #BayLog.debug("unregister io=%s", ch)
          if  not ((ch.kind_of? IO) || (ch.kind_of? OpenSSL::SSL::SSLSocket))
            raise ArgumentError
          end
          unregister_read(ch, @channels)
          unregister_write(ch, @channels)
        end

        def modify(ch, op)
          if  not ((ch.kind_of? IO) || (ch.kind_of? OpenSSL::SSL::SSLSocket))
            raise ArgumentError
          end
          if op & OP_READ != 0
            register_read(ch, @channels)
          else
            unregister_read(ch, @channels)
          end

          if op & OP_WRITE != 0
            register_write(ch, @channels)
          else
            unregister_write(ch, @channels)
          end
        end

        def get_op(ch)
          if not ((ch.kind_of? IO) || (ch.kind_of? OpenSSL::SSL::SSLSocket))
            raise ArgumentError
          end
          return @channels[ch]
        end

        def select(timeout_sec = nil)
          if timeout_sec == nil
            timeout_sec = 0
          end
          except_list = []

          read_list = []
          write_list = []
          @lock.synchronize do
            @channels.keys().each do |ch|
              if (@channels[ch] & OP_READ) != 0
                read_list << ch
              end
              if (@channels[ch] & OP_WRITE) != 0
                write_list << ch
              end
            end
          end
          #BayLog.debug("Select read_list=%s", read_list)
          #BayLog.debug("Select write_list=%s", write_list)
          selected_read_list, selected_write_list = Kernel.select(read_list, write_list, except_list, timeout_sec)

          result = {}
          if selected_read_list != nil
            selected_read_list.each do |ch|
              register_read(ch, result)
            end
          end

          if selected_write_list != nil
            selected_write_list.each do |ch|
              register_write(ch, result)
            end
          end

          return result
        end

        def count
          @lock.synchronize do
            return @channels.length
          end
        end

        private

        def register_read(ch, ch_list)
          @lock.synchronize do
            if ch_list.include?(ch)
              ch_list[ch] = (ch_list[ch] | OP_READ)
            else
              ch_list[ch] = OP_READ
            end
          end
        end

        def register_write(ch, ch_list)
          @lock.synchronize do
            if ch_list.include?(ch)
              ch_list[ch] = (ch_list[ch] | OP_WRITE)
            else
              ch_list[ch] = OP_WRITE
            end
          end
        end

        def unregister_read(ch, ch_list)
          @lock.synchronize do
            if ch_list.include?(ch)
              if ch_list[ch] == OP_READ
                ch_list.delete(ch)
              else
                ch_list[ch] = OP_WRITE
              end
            end
          end
        end


        def unregister_write(ch, ch_list)
          @lock.synchronize do
            if ch_list.include?(ch)
              if ch_list[ch] == OP_WRITE
                ch_list.delete(ch)
              else
                ch_list[ch] = OP_READ
              end
            end
          end
        end
      end
    end
  end
end

