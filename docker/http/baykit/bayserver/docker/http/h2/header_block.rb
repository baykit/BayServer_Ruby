module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class HeaderBlock

            INDEX = 1
            OVERLOAD_KNOWN_HEADER = 2
            NEW_HEADER = 3
            KNOWN_HEADER = 4
            UNKNOWN_HEADER = 5
            UPDATE_DYNAMIC_TABLE_SIZE = 6

            attr_accessor :op
            attr_accessor :index
            attr_accessor :name
            attr_accessor :value
            attr_accessor :size

            def self.pack(blk, acc)
              case blk.op
              when INDEX
                acc.put_hpack_int(blk.index, 7, 1)

              when OVERLOAD_KNOWN_HEADER
                raise RuntimeError.new("IllegalState")

              when NEW_HEADER
                raise RuntimeError.new("Illegal State")

              when KNOWN_HEADER
                acc.put_hpack_int(blk.index, 4, 0)
                acc.put_hpack_string(blk.value, false)

              when UNKNOWN_HEADER
                acc.put_byte(0)
                acc.put_hpack_string(blk.name, false)
                acc.put_hpack_string(blk.value, false)

              when UPDATE_DYNAMIC_TABLE_SIZE
                raise RuntimeError.new("Illegal state")
              end
            end


            def self.unpack(acc)
              blk = HeaderBlock.new
              index = acc.get_byte
              is_index_header_field = (index & 0x80) != 0
              if is_index_header_field
                # index header field
                #   0   1   2   3   4   5   6   7
                # +---+---+---+---+---+---+---+---+
                # | 1 |        Index (7+)         |
                # +---+---------------------------+
                blk.op = INDEX
                blk.index = index & 0x7F
              else
                # literal header field
                update_index = (index & 0x40) != 0
                if update_index
                  index = index & 0x3F
                  overload_index = (index != 0)
                  if overload_index
                    if index == 0x3F
                      index = index + acc.get_hpack_int_rest
                    end
                    blk.op = OVERLOAD_KNOWN_HEADER
                    blk.index = index
                    #   0   1   2   3   4   5   6   7
                    # +---+---+---+---+---+---+---+---+
                    # | 0 | 1 |      Index (6+)       |
                    # +---+---+-----------------------+
                    # | H |     Value Length (7+)     |
                    # +---+---------------------------+
                    # | Value String (Length octets)  |
                    # +-------------------------------+
                    blk.value = acc.get_hpack_string
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
                    blk.op = NEW_HEADER
                    blk.name = acc.get_hpack_string
                    blk.value = acc.get_hpack_string
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
                      size = size + acc.get_hpack_int_rest
                    end
                    blk.op = UPDATE_DYNAMIC_TABLE_SIZE
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
                        index = index + acc.get_hpack_int_rest
                      end
                      blk.op = KNOWN_HEADER
                      blk.index = index
                      blk.value = acc.get_hpack_string
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
                      blk.op = UNKNOWN_HEADER
                      blk.name = acc.get_hpack_string
                      blk.value = acc.get_hpack_string
                    end
                  end
                end
              end

              blk
            end

            def to_s
              "#{op} index=#{index} name=#{name} value=#{value}"
            end

          end
        end
      end
    end
  end
end

