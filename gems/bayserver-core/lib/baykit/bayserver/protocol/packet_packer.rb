module Baykit
  module BayServer
    module Protocol
      class PacketPacker
        include Baykit::BayServer::Util::Reusable # implements

        def reset()
        end

        def post(sip, pkt, flush, &lisnr)
          raise Sink.new() if sip.nil? || pkt.nil? || !block_given?
          # `block_given?` + `&lisnr` direct-forward avoids the implicit
          # Proc materialization that the previous `lisnr == nil` check
          # + wrapper `do |avail| lisnr.call(avail) end` block forced
          # on every call (~2 Procs per call attributed to this method
          # in stackprof obj-mode). Ruby 3+ lazy block forwarding lets
          # the block ride straight through to req_write without ever
          # being captured as a Proc here.
          return sip.transporter.req_write(
            sip.rudder,
            pkt.buf, 0, pkt.buf_len,
            nil,
            pkt,
            flush, &lisnr)
        end

      end
    end
  end
end
