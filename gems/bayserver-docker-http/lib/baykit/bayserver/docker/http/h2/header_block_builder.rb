module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class HeaderBlockBuilder

            def build_header_block(name, value, tbl)
              idx_list = tbl.get_idx_list(name)
              blk = nil

              idx_list.each do |idx|
                kv = tbl.get(idx)
                if kv != nil && value == kv.value
                  blk = HeaderBlock.new
                  blk.op = HeaderBlock::INDEX
                  blk.index = idx
                  break
                end
              end

              if blk == nil
                blk = HeaderBlock.new()
                if idx_list.length > 0
                  blk.op = HeaderBlock::KNOWN_HEADER
                  blk.index = idx_list[0]
                  blk.value = value
                else
                  blk.op = HeaderBlock::UNKNOWN_HEADER
                  blk.name = name
                  blk.value = value
                end
              end

              return blk
            end

            def build_status_block(status, tbl)
              st_index = -1

              status_index_list = tbl.get(":status")
              status_index_list.each do |index|
                kv = tbl.get(index)
                if kv != nil && status == kv.value.to_i
                  st_index = index
                  break
                end
              end

              blk = HeaderBlock.new()
              if st_index == -1
                blk.op = HeaderBlock::INDEX
                blk.index = st_index
              else
                blk.op = HeaderBlock::KNOWN_HEADER
                blk.index = status_index_list[0]
                blk.value = status.to_i
              end

              return blk
            end
          end
        end
      end
    end
  end
end

