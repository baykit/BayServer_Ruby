module Baykit
  module BayServer
    module Util
      class StringUtil
        class << self
          attr :falses
          attr :trues
        end

        @falses = ["no", "false", "0", "off"]
        @trues = ["yes", "true", "1", "on"]

        def StringUtil.set?(str)
          str != nil && str.length > 0
        end

        def StringUtil.empty?(str)
          !set?(str)
        end

        def StringUtil.alloc(len)
          String.new("", encoding: Encoding::ASCII_8BIT, capacity: len)
        end

        def StringUtil.realloc(buf, len)
          String.new(buf, encoding: Encoding::ASCII_8BIT, capacity: len)
        end

        def StringUtil.to_bytes(buf)
          buf.encode(encoding: Encoding::ASCII_8BIT)
        end

        def StringUtil.repeat(str, times)
          return Array.new(times, str).join("")
        end

        def StringUtil.indent(count)
          return repeat(" ", count);
        end

        def StringUtil.parse_bool(val)
          val = val.downcase()
          if @trues.include?(val)
            return true
          elsif @falses.include?(val)
            return false
          else
            BayLog.warn("Invalid boolean value: %s", val)
            return false
          end
        end

        def StringUtil.parse_size(val)
          val = val.downcase
          rate = 1
          if val.end_with?("b")
            val = val[0, val.length - 1]
          end

          if val.end_with?("k")
            val = val[0, val.length - 1]
            rate = 1024
          elsif val.end_with?("m")
            val = val[0, val.length - 1]
            rate = 1024 * 1024
          end

          Integer(val) * rate
        end
      end
    end
  end
end
