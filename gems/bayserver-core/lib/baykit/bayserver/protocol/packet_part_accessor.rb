require 'baykit/bayserver/sink'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Protocol
      class PacketPartAccessor
        include Baykit::BayServer
        include Baykit::BayServer::Util
        include Baykit::BayServer::Util::Reusable

        attr :packet
        attr :start
        attr :max_len
        attr :pos

        def initialize(pkt, start, max_len)
          @packet = pkt
          @start = start
          @max_len = max_len
          @pos = 0
        end

        def reset
          @pos = 0
        end

        def put_byte(b)
          buf = StringUtil.alloc(1)
          buf << b
          put_bytes(buf, 0, 1)
        end

        def put_bytes(buf, ofs=0, len=buf.length)
          if len > 0
            check_write(len)
            while @start + @pos + len > @packet.buf.length
              packet.expand
            end
            begin
              # bytesplice(index, length, src, src_index, src_length) is
              # the Ruby equivalent of System.arraycopy: it copies bytes
              # from src directly into self without first allocating a
              # substring (`buf[ofs, len]`) and without re-allocating
              # self. Drops two String allocations per call -- this path
              # is on every header / body chunk write.
              @packet.buf.bytesplice(@start + @pos, len, buf, ofs, len)
            rescue IndexError => e
              raise IndexError.new("data exceeds packet size: len=#{len} pktlen=#{buf.length - @start}")
            end

            forward(len)
          end
        end

        def put_short(val)
          h = val >> 8 & 0xFF
          l = val & 0xFF
          buf = StringUtil.alloc(2)
          buf << h << l
          put_bytes(buf)
        end

        def put_int(val)
          b1 = val >> 24 & 0xFF
          b2 = val >> 16 & 0xFF
          b3 = val >> 8 & 0xFF
          b4 = val & 0xFF
          buf = StringUtil.alloc(4)
          buf << b1 << b2 << b3 << b4
          put_bytes(buf)
        end

        def put_string(str)
          if str == nil
            raise Sink.new("nil")
          end
          put_bytes(StringUtil.to_bytes(str))
        end

        def get_byte
          # String#getbyte is the Ruby equivalent of Java's `byte[idx] & 0xFF`:
          # no allocation, returns the byte as an Integer in 0..255. The
          # previous `@packet.buf[idx].codepoints[0]` did two heap allocs
          # per byte (1-char String + Array), which dominated FCGI param
          # parsing (~200 get_byte calls per request).
          check_read(1)
          b = @packet.buf.getbyte(@start + @pos)
          @pos += 1
          return b
        end

        def get_bytes(buf, ofs=0, len=buf.length)
          if buf == nil
            raise Sink.new("nil")
          end

          check_read(len)
          # bytesplice(target_idx, target_len, src, src_idx, src_len) is
          # the Ruby equivalent of System.arraycopy: it copies bytes from
          # @packet.buf directly into buf without allocating the
          # intermediate substring that `@packet.buf[idx, len]` produces.
          buf.bytesplice(ofs, len, @packet.buf, @start + @pos, len)
          @pos += len
        end

        # Allocate a fresh ASCII-8BIT String of the next `len` bytes and
        # advance the read cursor. Equivalent to the (StringUtil.alloc +
        # get_bytes) two-step the FCGI param reader used to do, but in
        # one byteslice -- one alloc, one native copy, no intermediate
        # zero-fill of the destination.
        def read_substring(len)
          check_read(len)
          s = @packet.buf.byteslice(@start + @pos, len)
          @pos += len
          s
        end

        def get_short
          h = get_byte
          l = get_byte
          h << 8 | l
        end

        def get_int
          b1 = get_byte
          b2 = get_byte
          b3 = get_byte
          b4 = get_byte
          b1 << 24 | b2 << 16 | b3 << 8 | b4
        end

        def check_read(len)
          max_len = (@max_len >= 0) ? @max_len : (@packet.buf_len - @start)
          if @pos + len > max_len
            raise IOError.new("Invalid array index: @pos=#{@pos} @max=#{@max_len} len=#{len}")
          end
        end

        def check_write(len)
          if @max_len > 0 && @pos + len > @max_len
            raise IOError.new("Buffer overflow: @pos=#{@pos} @max=#{@max_len} len=#{len}")
          end
        end

        def forward(len)
          @pos += len
          if @start + @pos > @packet.buf_len
            @packet.buf_len = @start + @pos
          end
        end
      end
    end
  end
end
