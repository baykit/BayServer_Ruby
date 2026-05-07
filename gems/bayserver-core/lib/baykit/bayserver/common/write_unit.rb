require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Common
        # WriteUnit owns its byte buffer (@buf) and reuses it across
        # rents from the per-RudderState pool. init() copies bytes from
        # the caller's source buffer into @buf via a single bytesplice
        # so PacketPacker#post no longer needs to allocate a fresh
        # `pkt.buf[0, pkt.buf_len]` slice per packet. The write loop
        # tracks bytes already written via @wrote rather than slice!()
        # so the underlying String capacity is preserved between rents.
        class WriteUnit
          include Baykit::BayServer::Util::Reusable # implements (for ObjectStore)

          attr :buf
          attr_accessor :len
          attr_accessor :wrote
          attr :adr
          attr :tag
          attr :listener

          # ObjectStore factory uses a no-arg lambda; .new takes no args.
          # @buf is allocated once with empty content and grows in place
          # through bytesplice in init(); subsequent rents reuse the same
          # underlying String capacity.
          def initialize
            @buf = "".b
            @len = 0
            @wrote = 0
            @adr = nil
            @tag = nil
            @listener = nil
          end

          # Set fields after rent. Copies `src[ofs, len]` into @buf via
          # a single bytesplice. If @buf retained capacity from the
          # previous rent, no internal realloc; otherwise one heap
          # alloc to grow.
          def init(src, ofs, len, adr, tag, &lis)
            @buf.bytesplice(0, @buf.bytesize, src, ofs, len)
            @len = len
            @wrote = 0
            @adr = adr
            @tag = tag
            @listener = lis
          end

          # Bytes still to write.
          def remaining
            @len - @wrote
          end

          # Returns the buf slice that still needs to be written. For
          # the common full-write case (@wrote == 0) this is @buf
          # itself (no alloc). For the rare partial-retry path it
          # allocates a byteslice of the unsent tail.
          def remaining_buf
            @wrote == 0 ? @buf : @buf.byteslice(@wrote, @len - @wrote)
          end

          def done(buffer_available = true)
            @listener.call(buffer_available) if @listener
          end

          # Release strong references to the previous Packet (@tag),
          # callback Proc (@listener), and address so they can be GC'd
          # while the WriteUnit shell + @buf capacity stay cached for
          # the next rent.
          def reset
            @adr = nil
            @tag = nil
            @listener = nil
          end
        end
    end
  end
end
