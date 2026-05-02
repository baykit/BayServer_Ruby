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
          return sip.transporter.req_write(
            sip.rudder,
            pkt.buf[0, pkt.buf_len],
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
