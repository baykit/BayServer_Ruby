require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/tours/req_content_handler'

module Baykit
  module BayServer
    module Common
        class WarpData
          include Baykit::BayServer::Tours::ReqContentHandler # implements
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent

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

          ################################
          # Implements ReqContentHandler
          ################################
          def on_read_req_content(tur, buf, start, len, &lis)
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

              if !@started
                # The buffer will become corrupted due to reuse.
                buf = buf.dup()
              end

              @warp_ship.warp_handler.send_res_content(
                tur,
                buf,
                start + pos,
                post_len) do
                  tur.req.consumed(tur_id, len, &lis)
                end
              pos += max_len
            end
          end

          def on_end_req_content(tur)
            BayLog.debug("%s End req content tur=%s", @warp_ship, tur)
            @warp_ship.check_ship_id(@warp_ship_id)
            @warp_ship.warp_handler.send_end_tour(tur, false) do
              agt = GrandAgent.get(@warp_ship.agent_id)
              agt.net_multiplexer.req_read(@warp_ship.rudder)
            end
          end

          def on_abort_req(tur)
            BayLog.debug("%s on req abort tur=%s", @warp_ship, tur)
            @warp_ship.check_ship_id(@warp_ship_id)
            @warp_ship.abort(@warp_ship_id)
            return false # not aborted immediately
          end

          ################################
          # Other methods
          ################################

          def start
            if !@started
              BayLog.debug("%s Start Warp tour", self)
              @warp_ship.flush()
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
