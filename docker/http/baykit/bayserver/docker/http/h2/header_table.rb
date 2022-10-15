require 'baykit/bayserver/util/key_val'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class HeaderTable
            include Baykit::BayServer::Util

            PSEUDO_HEADER_AUTHORITY = ":authority"
            PSEUDO_HEADER_METHOD = ":method"
            PSEUDO_HEADER_PATH = ":path"
            PSEUDO_HEADER_SCHEME = ":scheme"
            PSEUDO_HEADER_STATUS = ":status"

            attr :idx_map
            attr :add_count
            attr :name_map

            def initialize
              @idx_map = []
              @add_count = 0
              @name_map = {}
            end

            def get(idx)
              if idx <= 0 || idx > HeaderTable.static_size + @idx_map.length
                raise RuntimeError "idx=#{idx} static=#{HeaderTable.static_size} dynamic=#{@idx_map.length}"
              end

              if idx <= HeaderTable.static_size
                kv = HeaderTable.static_table.idx_map[idx - 1]
              else
                kv = @idx_map[(idx - HeaderTable.static_size) - 1]
              end
              kv
            end

            def get_idx_list(name)
              dynamic_list = @name_map[name]
              static_list = HeaderTable.static_table.name_map[name]

              idx_list = []
              if static_list != nil
                idx_list.concat static_list
              end
              if dynamic_list != nil
                dynamic_list.each do |idx|
                  real_index = @add_count - idx + HeaderTable.static_size
                  idx_list << real_index
                end
              end
              return idx_list
            end

            def insert(name, value)
              @idx_map.insert(0, KeyVal.new(name, value))
              @add_count += 1
              add_to_name_map(name, @add_count)
            end

            def set_size(size)

            end

            def put(idx, name, value)
              if idx != @idx_map.length + 1
                raise RuntimeError.new("Illegal State")
              end
              @idx_map.append(KeyVal.new(name, value))
              add_to_name_map(name, idx)
            end

            private
            def add_to_name_map(name, idx)
              idx_list = @name_map[name]
              if idx_list == nil
                idx_list = []
                @name_map[name] = idx_list
              end
              idx_list.append(idx)
            end

            def self.create_dynamic_table()
              t = HeaderTable.new()
              t
            end

            class << self
              attr :static_table
              attr :static_size
            end
            @static_table = HeaderTable.new()
            @static_size = 0

            @static_table.put(1, PSEUDO_HEADER_AUTHORITY, nil)
            @static_table.put(2, PSEUDO_HEADER_METHOD, "GET")
            @static_table.put(3, PSEUDO_HEADER_METHOD, "POST")
            @static_table.put(4, PSEUDO_HEADER_PATH, "/")
            @static_table.put(5, PSEUDO_HEADER_PATH, "/index.html")
            @static_table.put(6, PSEUDO_HEADER_SCHEME, "http")
            @static_table.put(7, PSEUDO_HEADER_SCHEME, "https")
            @static_table.put(8, PSEUDO_HEADER_STATUS, "200")
            @static_table.put(9, PSEUDO_HEADER_STATUS, "204")
            @static_table.put(10, PSEUDO_HEADER_STATUS, "206")
            @static_table.put(11, PSEUDO_HEADER_STATUS, "304")
            @static_table.put(12, PSEUDO_HEADER_STATUS, "400")
            @static_table.put(13, PSEUDO_HEADER_STATUS, "404")
            @static_table.put(14, PSEUDO_HEADER_STATUS, "500")
            @static_table.put(15, "accept-charset", nil)
            @static_table.put(16, "accept-encoding", "gzip, deflate")
            @static_table.put(17, "accept-language", nil)
            @static_table.put(18, "accept-ranges", nil)
            @static_table.put(19, "accept", nil)
            @static_table.put(20, "access-control-allow-origin", nil)
            @static_table.put(21, "age", nil)
            @static_table.put(22, "allow", nil)
            @static_table.put(23, "authorization", nil)
            @static_table.put(24, "cache-control", nil)
            @static_table.put(25, "content-disposition", nil)
            @static_table.put(26, "content-encoding", nil)
            @static_table.put(27, "content-language", nil)
            @static_table.put(28, "content-length", nil)
            @static_table.put(29, "content-location", nil)
            @static_table.put(30, "content-range", nil)
            @static_table.put(31, "content-type", nil)
            @static_table.put(32, "cookie", nil)
            @static_table.put(33, "date", nil)
            @static_table.put(34, "etag", nil)
            @static_table.put(35, "expect", nil)
            @static_table.put(36, "expires", nil)
            @static_table.put(37, "from", nil)
            @static_table.put(38, "host", nil)
            @static_table.put(39, "if-match", nil)
            @static_table.put(40, "if-modified-since", nil)
            @static_table.put(41, "if-none-match", nil)
            @static_table.put(42, "if-range", nil)
            @static_table.put(43, "if-unmodified-since", nil)
            @static_table.put(44, "last-modified", nil)
            @static_table.put(45, "link", nil)
            @static_table.put(46, "location", nil)
            @static_table.put(47, "max-forwards", nil)
            @static_table.put(48, "proxy-authenticate", nil)
            @static_table.put(49, "proxy-authorization", nil)
            @static_table.put(50, "range", nil)
            @static_table.put(51, "referer", nil)
            @static_table.put(52, "refresh", nil)
            @static_table.put(53, "retry-after", nil)
            @static_table.put(54, "server", nil)
            @static_table.put(55, "set-cookie", nil)
            @static_table.put(56, "strict-transport-security", nil)
            @static_table.put(57, "transfer-encoding", nil)
            @static_table.put(58, "user-agent", nil)
            @static_table.put(59, "vary", nil)
            @static_table.put(60, "via", nil)
            @static_table.put(61, "www-authenticate", nil)

            @static_size = @static_table.idx_map.length

          end
        end
      end
    end
  end
end

