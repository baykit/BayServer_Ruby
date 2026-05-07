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

        # Sized to fit the typical body chunk (64K) plus a small header
        # without a single expand step. The pool reuses Packet instances,
        # and reset() now preserves the underlying buffer so subsequent
        # requests re-use the already-allocated capacity.
        INITIAL_BUF_SIZE = 128 * 1024

        attr :type
        attr :buf
        attr_accessor :buf_len
        attr :header_len
        attr :max_data_len
        attr :header_accessor
        attr :data_accessor

        def initialize(type, header_len, max_data_len)
          @type = type
          @header_len = header_len
          @max_data_len = max_data_len
          # Pre-fill to INITIAL_BUF_SIZE with zero bytes so the buffer's
          # length (used by put_bytes' expand check) starts at full
          # capacity. put_bytes overwrites in place via String#[]=, so
          # the pre-filled zeros never reach the wire.
          @buf = "\0" * INITIAL_BUF_SIZE
          @header_accessor = PacketPartAccessor.new(self, 0, header_len)
          @data_accessor = PacketPartAccessor.new(self, header_len, -1)
          reset
        end

        def reset
          # Do NOT clear @buf -- keeping it at its current length means
          # subsequent put_bytes calls hit the expand check only when the
          # request actually exceeds the current capacity, instead of
          # rebuilding from zero on every pooled rent.
          @buf_len = header_len
          @header_accessor.reset
          @data_accessor.reset
        end

        def data_len()
          return @buf_len - @header_len
        end

        def expand
          new_len = if @buf.length == 0 then 128 else @buf.length * 2 end
          @buf << "\0" * new_len
        end

        def to_s
          return "pkt[#{ClassUtil.get_local_name(self.class)}(#{@type})]"
        end
      end
    end
  end
end