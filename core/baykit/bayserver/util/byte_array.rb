require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Util
      class ByteArray
        INITIAL_BUF_SIZE = 8192 * 4

        attr :buf

        def initialize(buf = nil)
          if(buf == nil)
            @buf = StringUtil.alloc(INITIAL_BUF_SIZE)
          else
            @buf = buf
          end
        end

        def clear()
          @buf.clear()
        end

        def length()
          @buf.length()
        end

        def put_bytes(bytes, ofs = 0, len = bytes.length)
          if(bytes == nil)
            raise RuntimeError("nil bytes")
          end

          #while pos + len > @capacity
          #  extend_buf
          #end

          len.times do |i|
            if(bytes[ofs + i] == nil)
              raise RuntimeError.new("Invalid Data")
            end
            @buf.concat(bytes[ofs + i])
          end
        end

        private
        def extend_buf()
          @capacity *= 2
          new_buf = StringUtil.realloc(@buf, @capacity)
          @buf = new_buf
        end

      end
    end
  end
end
