require 'baykit/bayserver/protocol/package'
require 'baykit/bayserver/docker/http/h2/huffman/htree'

#
#   Http2 spec
#     https://www.rfc-editor.org/rfc/rfc7540.txt
#
#   Http2 Frame format
#   +-----------------------------------------------+
#   |                 Length (24)                   |
#   +---------------+---------------+---------------+
#   |   Type (8)    |   Flags (8)   |
#   +-+-+-----------+---------------+-------------------------------+
#   |R|                 Stream Identifier (31)                      |
#   +=+=============================================================+
#   |                   Frame Payload (0...)                      ...
#   +---------------------------------------------------------------+
#
module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2Packet < Baykit::BayServer::Protocol::Packet

            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Docker::Http::H2

            class H2HeaderAccessor < PacketPartAccessor
              def initialize(pkt, start, max_len)
                super
              end

              def put_int24(len)
                b1 = (len >> 16) & 0xFF
                b2 = (len >> 8) & 0xFF
                b3 = len & 0xFF
                buf = StringUtil.alloc(3)
                buf << b1 << b2 << b3
                put_bytes buf
              end
            end

            class H2DataAccessor < PacketPartAccessor
              include Baykit::BayServer::Docker::Http::H2::Huffman

              def initialize(pkt, start, max_len)
                super
              end

              def get_hpack_int(prefix, head)
                max_val = 0xFF >> (8 - prefix)

                first_byte = get_byte
                first_val = first_byte & max_val
                head[0] = first_byte >> prefix
                if first_val != max_val
                  first_val
                else
                  max_val + get_hpack_int_rest
                end
              end

              def get_hpack_int_rest
                rest = 0
                i = 0
                while true
                  data = get_byte
                  cont = (data & 0x80) != 0
                  value = data & 0x7F
                  rest = rest + (value << (i*7))
                  if !cont
                    break
                  end
                  i += 1
                end
                return rest
              end

              def get_hpack_string
                is_huffman = [nil]
                len = get_hpack_int(7, is_huffman)
                data = StringUtil.alloc(len)
                get_bytes data, 0, len
                if is_huffman[0] == 1
                  return HTree.decode(data)
                else
                  # ASCII
                  return data
                end
              end

              def put_hpack_int(val, prefix, head)
                max_val = 0xFF >> (8 -prefix)
                head_val = (head << prefix) & 0xFF
                if val < max_val
                  put_byte (val | head_val)
                else
                  put_byte (head_val | max_val)
                  put_hpack_int_rest(val - max_val)
                end
              end

              def put_hpack_int_rest(val)
                while true
                  data = val & 0x7F
                  next_val = val >> 7
                  if next_val == 0
                    put_byte(data)
                    break
                  else
                    put_byte(data | 0x80)
                    val = next_val
                  end
                end
              end

              def put_hpack_string(value, is_haffman)
                if is_haffman
                  raise RuntimeError.new "Illegal State"
                else
                  put_hpack_int(value.length, 7, 0)
                  put_bytes(value)
                end
              end
            end

            MAX_PAYLOAD_LEN = 0x00FFFFFF         # = 2^24-1 = 16777215 = 16MB-1
            DEFAULT_PAYLOAD_MAXLEN = 0x00004000  # = 2^14 = 16384 = 16KB
            FRAME_HEADER_LEN = 9

            NO_ERROR = 0x0
            PROTOCOL_ERROR = 0x1
            INTERNAL_ERROR = 0x2
            FLOW_CONTROL_ERROR = 0x3
            SETTINGS_TIMEOUT = 0x4
            STREAM_CLOSED = 0x5
            FRAME_SIZE_ERROR = 0x6
            REFUSED_STREAM = 0x7
            CANCEL = 0x8
            COMPRESSION_ERROR = 0x9
            CONNECT_ERROR = 0xa
            ENHANCE_YOUR_CALM = 0xb
            INADEQUATE_SECURITY = 0xc
            HTTP_1_1_REQUIRED = 0xd

            attr_accessor :flags
            attr_accessor :stream_id

            def initialize(type)
              super(type, FRAME_HEADER_LEN, DEFAULT_PAYLOAD_MAXLEN)
              @flags = H2Flags::FLAGS_NONE
              @stream_id = -1
            end

            def reset
              @flags = H2Flags::FLAGS_NONE
              @stream_id = -1
              super
            end

            def pack_header
              acc = new_h2_header_accessor()
              acc.put_int24(data_len())
              acc.put_byte(@type)
              acc.put_byte(@flags.flags)
              acc.put_int(H2Packet.extract_int31(stream_id))
            end

            def new_h2_header_accessor
              H2HeaderAccessor.new(self, 0, @header_len)
            end

            def new_h2_data_accessor
              H2DataAccessor.new(self, @header_len, -1)
            end

            def self.extract_int31(val)
              val & 0x7FFFFFFF
            end

            def self.extract_flag(val)
              (val & 0x80000000) >> 31 & 1
            end

            def self.consolidate_flag_and_int32(flag, val)
              ((flag & 1) << 31) | (val & 0x7FFFFFFF)
            end

            def self.make_stream_dependency32(excluded, dep)
              (excluded ? 1 : 0) << 31 | extract_int31(dep)
            end

            def to_s
              "H2Packet(#{@type}) headerLen=#{@header_len} dataLen=#{data_len()} stm=#{@stream_id} flags=#{@flags}"
            end
          end
        end
      end
    end
  end
end


