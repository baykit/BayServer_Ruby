require 'baykit/bayserver/rudders/rudder'
require 'baykit/bayserver/rudders/rudder_base'

module Baykit
  module BayServer
    module Rudders
      class IORudder < RudderBase

        attr :io
        attr :non_blocking
        # Cached peer / local addresses, populated once at accept time
        # so the per-request hot path can skip getpeername / getsockname
        # syscalls and the unpack_sockaddr_in parse those return values
        # need. Stay nil for rudders that are not accepted client sockets
        # (listening sockets, file descriptors, etc.) -- callers fall
        # back to the live syscall path when nil.
        attr_accessor :remote_address
        attr_accessor :remote_port
        attr_accessor :server_address

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