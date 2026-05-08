module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class HeaderBlockAnalyzer

            attr :name
            attr :value
            # The original header name before any renaming (e.g. :authority -> host).
            # Needed by pseudo-header validation that must distinguish :authority
            # from a literal "host" header the client might also send.
            attr :raw_name
            attr :method
            attr :path
            attr :scheme
            attr :status
            # True iff raw_name started with ':' (i.e. this was a pseudo-header).
            attr :pseudo

            def clear
              @name = nil
              @value = nil
              @raw_name = nil
              @method = nil
              @path = nil
              @scheme = nil
              @status = nil
              @pseudo = false
            end

            def analyze_header_block(blk, tbl)
              clear
              case blk.op
              when HeaderBlock::INDEX
                begin
                  kv = tbl.get(blk.index)
                rescue ArgumentError => e
                  raise Baykit::BayServer::Protocol::ProtocolException.new("Invalid header index: #{blk.index}")
                end
                if kv == nil
                  raise Baykit::BayServer::Protocol::ProtocolException.new("Invalid header index: #{blk.index}")
                end
                @name = kv.name
                @value = kv.value

              when HeaderBlock::KNOWN_HEADER, HeaderBlock::OVERLOAD_KNOWN_HEADER
                begin
                  kv = tbl.get(blk.index)
                rescue ArgumentError => e
                  raise Baykit::BayServer::Protocol::ProtocolException.new("Invalid header index: #{blk.index}")
                end
                if kv == nil
                  raise Baykit::BayServer::Protocol::ProtocolException.new("Invalid header index: #{blk.index}")
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

              @raw_name = @name
              @pseudo = @name != nil && !@name.empty? && @name[0] == ":"

              if @pseudo
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

