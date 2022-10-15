require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/class_util'

#
# Packet format
#   +---------------------------+
#  +  Header(type, length etc) +
#  +---------------------------+
#  +  Data(payload data)       +
#  +---------------------------+
#
module Baykit
  module BayServer
    module Protocol
      class Packet
        include Baykit::BayServer::Util
        include Baykit::BayServer::Util::Reusable # implements

        INITIAL_BUF_SIZE = 8192 * 4

        attr :type
        attr :buf
        attr_accessor :buf_len
        attr :header_len
        attr :max_data_len

        def initialize(type, header_len, max_data_len)
          @type = type
          @header_len = header_len
          @max_data_len = max_data_len
          @buf = StringUtil.alloc(INITIAL_BUF_SIZE)
          reset
        end

        def reset
          @buf.clear()
          header_len.times do |i| @buf << 0 end
          @buf_len = header_len
        end

        def data_len()
          return @buf_len - @header_len
        end

        def expand
          @buf = StringUtil.realloc(@buf, @buf.length * 2)
        end

        def new_header_accessor()
          return PacketPartAccessor.new(self, 0, @header_len)
        end

        def new_data_accessor()
          return PacketPartAccessor.new(self, @header_len, -1)
        end

        def to_s
          return "pkt[#{ClassUtil.get_local_name(self.class)}(#{@type})]"
        end
      end
    end
  end
end