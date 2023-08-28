module Baykit
  module BayServer
    module Protocol
      class PacketPacker
        include Baykit::BayServer::Util::Reusable # implements

        def reset()
        end

        def post(postman, pkt, &lisnr)
          if postman == nil || pkt == nil || lisnr == nil
            raise Sink.new()
          end
          postman.post(pkt.buf[0, pkt.buf_len], nil, pkt) do
            lisnr.call()
          end
        end

        def flush(postman)
          postman.flush()
        end

        def end(postman)
          postman.post_end()
        end

      end
    end
  end
end
