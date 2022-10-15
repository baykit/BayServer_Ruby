module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class HeaderBlockAnalyzer

            attr :name
            attr :value
            attr :method
            attr :path
            attr :scheme
            attr :status

            def clear
              @name = nil
              @value = nil
              @method = nil
              @path = nil
              @scheme = nil
              @status = nil
            end

            def analyze_header_block(blk, tbl)
              clear
              case blk.op
              when HeaderBlock::INDEX
                kv = tbl.get(blk.index)
                if kv == nil
                  raise RuntimeError.new "Invalid header index: #{blk.index}"
                end
                @name = kv.name
                @value = kv.value

              when HeaderBlock::KNOWN_HEADER, HeaderBlock::OVERLOAD_KNOWN_HEADER
                kv = tbl.get(blk.index)
                if kv == nil
                  raise RuntimeError.new "Invalid header index: #{blk.index}"
                end
                @name = kv.name
                @value = blk.value
                if blk.op == HeaderBlock::OVERLOAD_KNOWN_HEADER
                  tbl.insert(@name, @value)
                end

              when HeaderBlock::NEW_HEADER
                @name = blk.name
                @value = blk.value
                tbl.insert(@name, @value)

              when HeaderBlock::UNKNOWN_HEADER
                @name = blk.name
                @value = blk.value

              when HeaderBlock::UPDATE_DYNAMIC_TABLE_SIZE
                tbl.set_size(blk.size)

              else
                raise RuntimeError.new("Illegal state")

              end

              if @name != nil && @name[0] == ":"
                case @name
                when HeaderTable::PSEUDO_HEADER_AUTHORITY
                  @name = "host"

                when HeaderTable::PSEUDO_HEADER_METHOD
                  @method = @value

                when HeaderTable::PSEUDO_HEADER_PATH
                  @path = @value

                when HeaderTable::PSEUDO_HEADER_SCHEME
                  @scheme = @value

                when HeaderTable::PSEUDO_HEADER_STATUS
                  @status = @value
                end
              end
            end
          end
        end
      end
    end
  end
end

