require 'baykit/bayserver/util/data_consume_listener'

module Baykit
  module BayServer
    module Protocol
      class CommandPacker
        include Baykit::BayServer::Util::Reusable # implements

        include Baykit::BayServer::Util

        attr :pkt_packer
        attr :pkt_store

        def initialize(pkt_packer, store)
          @pkt_packer = pkt_packer
          @pkt_store = store
        end

        def reset()

        end

        def post(sip, cmd, flush, &lisnr)
          pkt = @pkt_store.rent(cmd.type)
          begin
            cmd.pack(pkt)
            return @pkt_packer.post(sip, pkt, flush) do |avail|
              @pkt_store.Return(pkt)
              if lisnr != nil
                lisnr.call(avail)
              end
            end
          rescue IOError => e
            @pkt_store.Return(pkt)
            raise e
          end
        end

      end
    end
  end
end
