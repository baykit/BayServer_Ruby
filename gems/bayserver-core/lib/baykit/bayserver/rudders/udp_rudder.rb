require 'baykit/bayserver/rudders/rudder'
require 'baykit/bayserver/rudders/rudder_base'

module Baykit
  module BayServer
    module Rudders
      # UdpRudder wraps a UDP Socket (SOCK_DGRAM). Unlike IORudder, it uses
      # recvfrom_nonblock to capture the sender's address, and send_nonblock
      # to direct outgoing datagrams to a specific destination.
      class UdpRudder < RudderBase

        attr_reader :io, :last_sender

        def initialize(io)
          @io         = io
          @last_sender = nil  # set by read(); holds [family, port, hostname, ip]
        end

        def to_s
          "UdpRudder:#{@io}"
        end

        def key
          @io
        end

        def set_non_blocking
          @io.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
        end

        # Reads one UDP datagram. Sets @last_sender to the sender's
        # [family, port, hostname, ip] so the caller can route replies.
        def read(buf, len)
          data, sender = @io.recvfrom_nonblock(len)
          @last_sender = sender
          buf.replace(data)
          data.bytesize
        rescue IO::WaitReadable
          raise
        rescue EOFError
          0
        end

        # Directed send — sends buf to the given Addrinfo or recvfrom
        # sender-tuple [family, port, hostname, ip].
        def send_to(buf, adr)
          ip, port = extract_ip_port(adr)
          @io.send(buf, 0, Socket.pack_sockaddr_in(port, ip))
        rescue IO::WaitWritable
          0
        end

        def write(buf)
          @io.write_nonblock(buf)
        end

        def close
          @io.close
        end

        def udp? = true

        private

        def extract_ip_port(adr)
          if adr.is_a?(Array)
            [adr[3], adr[1]]
          elsif adr.respond_to?(:ip_address)
            [adr.ip_address, adr.ip_port]
          else
            [adr.to_s, 0]
          end
        end
      end
    end
  end
end
