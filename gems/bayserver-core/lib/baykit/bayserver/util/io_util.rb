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
      end
    end
  end
end
