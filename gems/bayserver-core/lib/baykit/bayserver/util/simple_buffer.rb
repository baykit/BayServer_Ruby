require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Util
      class SimpleBuffer
        include Baykit::BayServer::Util::Reusable  # implements
        INITIAL_BUFFER_SIZE = 32768

        attr :buf
        attr :length
        attr :capacity

        def initialize(init=INITIAL_BUFFER_SIZE)
          @capacity = init
          @buf = StringUtil.alloc(@capacity)
          @length = 0
        end

        def bytes()
          return buf
        end

        def reset()
          # clear for security reason
          @buf.clear()
          @length = 0
        end

        def put_byte(b)
          put(b.chr, 0, 1);
        end

        def put(bytes, pos=0, len=bytes.length)
          while @length + len > capacity
            extend_buf
          end

          len.times do |i|
            @buf[@length + i] = bytes[pos + i]
          end
          @length += len
        end

        def extend_buf()
          @capacity *= 2
          @buf = StringUtil.realloc(@buf, @capacity)
        end
      end
    end
  end
end
