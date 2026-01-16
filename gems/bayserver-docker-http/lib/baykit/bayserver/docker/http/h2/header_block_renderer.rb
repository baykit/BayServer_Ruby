require 'baykit/bayserver/docker/http/h2/header_block'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class HeaderBlockRenderer

            include Baykit::BayServer::Util

            attr :buf

            def initialize(buf)
              @buf = buf
            end

            def render_header_blocks(header_blocks)

              header_blocks.each do |blk|
                render_header_block(blk)
              end
            end

            private

            def render_header_block(blk)
              case blk.op
              when HeaderBlock::INDEX
                put_hpack_int(blk.index, 7, 1)

              when HeaderBlock::OVERLOAD_KNOWN_HEADER
                raise RuntimeError.new("IllegalState")

              when HeaderBlock::NEW_HEADER
                raise RuntimeError.new("Illegal State")

              when HeaderBlock::KNOWN_HEADER
                put_hpack_int(blk.index, 4, 0)
                put_hpack_string(blk.value, false)

              when HeaderBlock::UNKNOWN_HEADER
                put_byte(0)
                put_hpack_string(blk.name, false)
                put_hpack_string(blk.value, false)

              when HeaderBlock::UPDATE_DYNAMIC_TABLE_SIZE
                raise RuntimeError.new("Illegal state")
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

            def put_byte(val)
              @buf.put_byte(val)
            end

            def put_bytes(data)
              @buf.put(data)
            end

          end
        end
      end
    end
  end
end

