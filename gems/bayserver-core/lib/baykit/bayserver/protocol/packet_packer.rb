module Baykit
  module BayServer
    module Protocol
      class PacketPacker
        include Baykit::BayServer::Util::Reusable # implements

        def reset()
        end

        def post(sip, pkt, flush, &lisnr)
          if sip == nil || pkt == nil || lisnr == nil
            raise Sink.new()
          end
          # Pass pkt.buf + (0, pkt.buf_len) by reference. The downstream
          # WriteUnit#init copies these bytes into its own retained
          # buffer via a single bytesplice, eliminating the previous
          # `pkt.buf[0, pkt.buf_len]` String slice allocation per
          # packet.
          return sip.transporter.req_write(
            sip.rudder,
            pkt.buf, 0, pkt.buf_len,
            nil,
            pkt,
            flush) do |avail|
            lisnr.call(avail)
          end
        end

      end
    end
  end
end
