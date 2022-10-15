module Baykit
  module BayServer
    module Util
      class URLDecoder

        def self.decode(str, enc)
          parse_special(str, enc)
        end

        def self.parse_special(str, enc)
          arr = ByteArray.new
          index = 0

          while(index < str.length)
            c = str[index]
            case c
            when '+'
              arr.put_bytes(c)
              index = index + 1

            when '%'
              hex_str = str[index + 1 .. index + 2]
              ch = hex_str.hex
              arr.put_bytes([ch])
              index += 3

            else
              arr.put_bytes(c)
              index += 1
            end
          end

          if(StringUtil.empty?(enc))
            return arr.buf
          else
            return arr.buf.encode(enc)
          end
        end
      end
    end
  end
end
