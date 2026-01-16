require 'baykit/bayserver/docker/http/h2/header_block'
require 'baykit/bayserver/docker/http/h2/huffman/htree'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class HeaderBlockParser

            include Baykit::BayServer::Util
            include Baykit::BayServer::Docker::Http::H2::Huffman

            attr :buf
            attr :start
            attr :pos
            attr :length


            def initialize(buf, start, length)
              @buf = buf
              @start = start
              @pos = 0
              @length = length
            end

            def parse_header_blocks

              header_blocks = []

              while @pos < @length
                blk = parse_header_block()
                BayLog.trace("h2: header block read: %s", blk)
                header_blocks << blk
              end

              return header_blocks
            end


            private
            def parse_header_block()
              blk = HeaderBlock.new
              index = get_byte
              is_index_header_field = (index & 0x80) != 0
              if is_index_header_field
                # index header field
                #   0   1   2   3   4   5   6   7
                # +---+---+---+---+---+---+---+---+
                # | 1 |        Index (7+)         |
                # +---+---------------------------+
                blk.op = HeaderBlock::INDEX
                blk.index = index & 0x7F
              else
                # literal header field
                update_index = (index & 0x40) != 0
                if update_index
                  index = index & 0x3F
                  overload_index = (index != 0)
                  if overload_index
                    if index == 0x3F
                      index = index + get_hpack_int_rest
                    end
                    blk.op = HeaderBlock::OVERLOAD_KNOWN_HEADER
                    blk.index = index
                    #   0   1   2   3   4   5   6   7
                    # +---+---+---+---+---+---+---+---+
                    # | 0 | 1 |      Index (6+)       |
                    # +---+---+-----------------------+
                    # | H |     Value Length (7+)     |
                    # +---+---------------------------+
                    # | Value String (Length octets)  |
                    # +-------------------------------+
                    blk.value = get_hpack_string
                  else
                    # new header name
                    #   0   1   2   3   4   5   6   7
                    # +---+---+---+---+---+---+---+---+
                    # | 0 | 1 |           0           |
                    # +---+---+-----------------------+
                    # | H |     Name Length (7+)      |
                    # +---+---------------------------+
                    # |  Name String (Length octets)  |
                    # +---+---------------------------+
                    # | H |     Value Length (7+)     |
                    # +---+---------------------------+
                    # | Value String (Length octets)  |
                    # +-------------------------------+
                    blk.op = HeaderBlock::NEW_HEADER
                    blk.name = get_hpack_string
                    blk.value = get_hpack_string
                  end
                else
                  update_dynamic_table_size = (index & 0x20) != 0
                  if update_dynamic_table_size
                    #   0   1   2   3   4   5   6   7
                    # +---+---+---+---+---+---+---+---+
                    # | 0 | 0 | 1 |   Max size (5+)   |
                    # +---+---------------------------+
                    size = index & 0x1F
                    if size == 0x1F
                      size = size + get_hpack_int_rest
                    end
                    blk.op = HeaderBlock::UPDATE_DYNAMIC_TABLE_SIZE
                    blk.size = size
                  else
                    # not update index
                    index = (index & 0xF)
                    if index != 0
                      #   0   1   2   3   4   5   6   7
                      # +---+---+---+---+---+---+---+---+
                      # | 0 | 0 | 0 | 0 |  Index (4+)   |
                      # +---+---+-----------------------+
                      # | H |     Value Length (7+)     |
                      # +---+---------------------------+
                      # | Value String (Length octets)  |
                      # +-------------------------------+
                      #
                      # OR
                      #
                      #   0   1   2   3   4   5   6   7
                      # +---+---+---+---+---+---+---+---+
                      # | 0 | 0 | 0 | 1 |  Index (4+)   |
                      # +---+---+-----------------------+
                      # | H |     Value Length (7+)     |
                      # +---+---------------------------+
                      # | Value String (Length octets)  |
                      # +-------------------------------+
                      if index == 0xF
                        index = index + get_hpack_int_rest
                      end
                      blk.op = HeaderBlock::KNOWN_HEADER
                      blk.index = index
                      blk.value = get_hpack_string
                    else
                      # literal header field
                      #   0   1   2   3   4   5   6   7
                      # +---+---+---+---+---+---+---+---+
                      # | 0 | 0 | 0 | 0 |       0       |
                      # +---+---+-----------------------+
                      # | H |     Name Length (7+)      |
                      # +---+---------------------------+
                      # |  Name String (Length octets)  |
                      # +---+---------------------------+
                      # | H |     Value Length (7+)     |
                      # +---+---------------------------+
                      # | Value String (Length octets)  |
                      # +-------------------------------+
                      #
                      # OR
                      #
                      #   0   1   2   3   4   5   6   7
                      # +---+---+---+---+---+---+---+---+
                      # | 0 | 0 | 0 | 1 |       0       |
                      # +---+---+-----------------------+
                      # | H |     Name Length (7+)      |
                      # +---+---------------------------+
                      # |  Name String (Length octets)  |
                      # +---+---------------------------+
                      # | H |     Value Length (7+)     |
                      # +---+---------------------------+
                      # | Value String (Length octets)  |
                      # +-------------------------------+
                      #
                      blk.op = HeaderBlock::UNKNOWN_HEADER
                      blk.name = get_hpack_string
                      blk.value = get_hpack_string
                    end
                  end
                end
              end

              blk
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
              get_bytes data, len
              if is_huffman[0] == 1
                return HTree.decode(data)
              else
                # ASCII
                return data
              end
            end

            def get_byte
              if @pos >= @length
                raise ArgumentError.new("@pos=#{@pos} @len=#{@length}")
              end

              b = @buf[@start + @pos].ord & 0xff
              @pos += 1
              return b
            end

            def get_bytes(buf, len)
              buf.replace(@buf[@start + @pos, len])
              @pos += len
            end

          end
        end
      end
    end
  end
end

