require 'baykit/bayserver/rudders/rudder'

module Baykit
  module BayServer
    module Rudders
      class IORudder
        include Rudder

        attr :io
        attr :non_blocking

        def initialize(io)
          @io = io
        end

        def to_s
          return "IORudder:" + @io.to_s
        end
        def key
          return @io
        end

        def set_non_blocking()
          @non_blocking = true
        end

        def read(buf, len)
          begin
            if @non_blocking
              buf = @io.read_nonblock(len, buf)
            else
              buf = @io.readpartial(len, buf)
            end
            if buf == nil
              return 0
            else
              return buf.length
            end
          rescue EOFError => e
            return 0
          end
        end

        def write(buf)
          if @non_blocking
            return @io.write_nonblock(buf)
          else
            return @io.write(buf)
          end
        end

        def close
          @io.close()
        end

        def io
          return @io
        end
      end
    end
  end
end