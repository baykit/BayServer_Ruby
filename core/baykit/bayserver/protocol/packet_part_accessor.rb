require 'baykit/bayserver/sink'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Protocol
      class PacketPartAccessor
        include Baykit::BayServer
        include Baykit::BayServer::Util

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

        def put_byte(b)
          buf = StringUtil.alloc(1)
          buf << b
          put_bytes(buf, 0, 1)
        end

        def put_bytes(buf, ofs=0, len=buf.length)
          if len > 0
            check_write(len)
            #while(@start + @pos + len > @packet.buf.length)
            #  packet.expand()
            #end
            begin
              @packet.buf[@start + @pos, len] = buf[ofs, len]
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
          buf = StringUtil.alloc(1)
          get_bytes(buf, 0, 1)
          buf[0].codepoints[0]
        end

        def get_bytes(buf, ofs=0, len=buf.length)
          if buf == nil
            raise Sink.new("nil")
          end

          check_read(len)
          buf[ofs, len] = @packet.buf[@start + @pos, len]
          @pos += len
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
          max_len = (@max_len >= 0) ? @max_len : (@packet.buf.length - @start)
          if @pos + len > max_len
            raise Sink.new("Invalid array index")
          end
        end

        def check_write(len)
          if @max_len > 0 && @pos + len > @max_len
            raise Sink.new("Buffer overflow")
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
