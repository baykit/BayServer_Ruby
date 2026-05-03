module Baykit
  module BayServer
    module Util
      class IOUtil
        def IOUtil.read_int32(io)
          data = "    "
          begin
            dt = io.read_nonblock(4, data)
            if dt == nil
              return nil
            end
          rescue EOFError => e
            return nil
          end
          data = data.codepoints
          #print("IO.read->" + data[0].to_s + "," + data[1].to_s + "," + data[2].to_s + "," + data[3].to_s)
          return data[0] << 24 | (data[1]<< 16 & 0xFF0000) | (data[2] << 8 & 0xFF00) | (data[3] & 0xFF)
        end

        def IOUtil.write_int32(io, i)
          io.write([i].pack("N"))
        end

        def IOUtil.get_sock_recv_buf_size(skt)
          return skt.getsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF).int
        end

        # Returns [ip_string, port_int] for the peer end of an
        # accepted socket. SSLSocket is unwrapped to the underlying
        # TCP socket. Uses the Addrinfo accessors that
        # Socket#remote_address returns -- skips the
        # Socket.unpack_sockaddr_in parse, which on profiling was the
        # single hottest non-syscall frame on a 128B HTTP plain
        # workload (~16% of CPU). Caller is expected to memoize the
        # result for the life of the connection.
        def IOUtil.get_remote_address(io)
          io = io.io if io.kind_of?(::OpenSSL::SSL::SSLSocket)
          ai = io.remote_address
          [ai.ip_address, ai.ip_port]
        end

        # Returns ip_string for the local (server-side) end of a
        # socket. Same SSL-unwrap and Addrinfo-based shortcut as
        # get_remote_address. Caller is expected to memoize.
        def IOUtil.get_server_address(io)
          io = io.io if io.kind_of?(::OpenSSL::SSL::SSLSocket)
          io.local_address.ip_address
        end
      end
    end
  end
end
