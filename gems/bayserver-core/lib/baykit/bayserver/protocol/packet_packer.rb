module Baykit
  module BayServer
    module Protocol
      class PacketPacker
        include Baykit::BayServer::Util::Reusable # implements

        def reset()
        end

        def post(sip, pkt, &lisnr)
          if sip == nil || pkt == nil || lisnr == nil
            raise Sink.new()
          end
          sip.transporter.req_write(
            sip.rudder,
            pkt.buf[0, pkt.buf_len],
            nil,
            pkt) do
            lisnr.call()
          end
        end

      end
    end
  end
end
