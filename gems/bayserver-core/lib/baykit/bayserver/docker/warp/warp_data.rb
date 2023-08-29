require 'baykit/bayserver/tours/req_content_handler'

module Baykit
  module BayServer
    module Docker
      module Warp
        class WarpData
          include Baykit::BayServer::Tours::ReqContentHandler # implements
          include Baykit::BayServer::Util

          attr :warp_ship
          attr :warp_ship_id
          attr :warp_id
          attr :req_headers
          attr :res_headers
          attr :started
          attr :ended

          def initialize(warp_ship, warp_id)
            @warp_ship = warp_ship
            @warp_ship_id = warp_ship.id()
            @warp_id = warp_id
            @req_headers = Headers.new
            @res_headers = Headers.new
            @started = false
            @ended = false
          end

          def on_read_content(tur, buf, start, len)
            BayLog.debug("%s Read req content tur=%s len=%d", @warp_ship, tur, len);
            @warp_ship.check_ship_id(@warp_ship_id)
            max_len = @warp_ship.protocol_handler.max_req_packet_data_size()
            pos = 0
            while pos < len
              post_len = len - pos
              if post_len > max_len
                post_len = max_len
              end

              tur_id = tur.id()
              @warp_ship.warp_handler.post_warp_contents(
                tur,
                buf,
                start + pos,
                post_len) do
                  tur.req.consumed(tur_id, len)
                end
              pos += max_len
            end
          end

          def on_end_content(tur)
            BayLog.debug("%s End req content tur=%s", @warp_ship, tur)
            @warp_ship.warp_handler.post_warp_end(tur)
          end

          def on_abort(tur)
            BayLog.debug("%s on req abort tur=%s", @warp_ship, tur)
            @warp_ship.check_ship_id(@warp_ship_id)
            @warp_ship.abort(@warp_ship_id)
            return false # not aborted immediately
          end


          def start
            if !@started
              @warp_ship.protocol_handler.command_packer.flush(@warp_ship)
              BayLog.debug("%s Start Warp tour", self)
              @started = true
            end
          end

          def to_s
            return "#{@warp_ship} wtur##{@warp_id}"
          end

          def self.get(tur)
            return tur.req.content_handler
          end
        end
      end
    end
  end
end
