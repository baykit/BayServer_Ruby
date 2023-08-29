require 'baykit/bayserver/util/key_val'

module Baykit
  module BayServer
    module Util
      class KeyValListParser

        attr :item_sep
        attr :kv_sep

        def initialize(item_sep = "&", key_val_sep = "=")
          @item_sep = item_sep
          @kv_sep = key_val_sep
        end

        def parse(str)
          list = []
          buf = ""
          str.each do |c|
            if(c == @item_sep)
              list.append(divide_param(buf))
              buf.clear()
            else
              buf.concat(c)
            end
          end
          if(buf.length > 0)
            list.append(divide_param(buf))
          end

          return list
        end

        private
        def divide_param(str)
          pos = str.index @kv_sep
          if(pos == nil)
            name = str
            value = ""
          else
            name = str[0 .. pos]
            value = str[pos + 1 .. -1]
          end

          name.strip!
          KeyVal.new(name, value)
        end

      end
    end
  end
end

