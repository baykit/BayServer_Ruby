require 'baykit/bayserver/util/counter'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/docker/warp/warp_ship'

module Baykit
  module BayServer
    module Docker
      module Warp
        class WarpShip < Baykit::BayServer::WaterCraft::Ship
          include Baykit::BayServer::Agent
          include Baykit::BayServer::WaterCraft
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Util

          attr :tour_map
          attr :docker

          attr_accessor :connected
          attr :socket_timeout_sec
          attr :lock


          def initialize()
            super
            @docker = nil
            @socket_timeout_sec = nil
            @tour_map = {}
            @lock = Mutex.new()
            @connected = false
          end

          def to_s()
            return "warp##{@ship_id}/#{@object_id}[#{protocol}]"
          end

          ######################################################
          # Implements Reusable
          ######################################################

          def reset()
            super
            if !@tour_map.empty?
              BayLog.error("BUG: Some tours is active: %s", @tour_map)
            end
            @connected = false
          end


          ######################################################
          # Other methods
          ######################################################
          def init_warp(skt, agt, tp, dkr, proto_hnd)
            init(skt, agt, tp)
            @docker = dkr
            @socket_timeout_sec = @docker.timeout_sec >= 0 ? @docker.timeout_sec : BayServer.harbor.socket_timeout_sec
            set_protocol_handler(proto_hnd)
          end

          def warp_handler
            return @protocol_handler
          end

          def start_warp_tour(tur)
            w_hnd = warp_handler()
            warp_id = w_hnd.next_warp_id()
            wdat = w_hnd.new_warp_data(warp_id)
            BayLog.debug("%s new warp tour related to %s", wdat, tur)
            tur.req.set_content_handler(wdat)

            BayLog.debug("%s start: warpId=%d", wdat, warp_id);
            if @tour_map.key?(warp_id)
              raise Sink.new("warpId exists")
            end

            @tour_map[warp_id] = [tur.id(), tur]
            w_hnd.post_warp_headers(tur)

            if @connected
              BayLog.debug("%s is already connected. Start warp tour:%s", wdat, tur);
              wdat.start
            end
          end

          def end_warp_tour(tur)
            wdat = WarpData.get(tur)
            BayLog.debug("%s end warp tour: started=%s ended=%s", tur, wdat.started, wdat.ended)

            if(!@tour_map.include?(wdat.warp_id))
              raise Sink.new("%s WarpId not in tourMap: %d", tur, wdat.warp_id);
            else
              @tour_map.delete wdat.warp_id
            end
            @docker.keep_ship(self)
          end

          def notify_service_unavailable(msg)
            notify_error_to_owner_tour(HttpStatus::SERVICE_UNAVAILABLE, msg)
          end

          def get_tour(warp_id, must=true)
            pair = @tour_map[warp_id]
            if pair != nil
              tur = pair[1]
              tur.check_tour_id pair[0]
              if !WarpData.get(tur).ended
                return tur
              end
            end

            if must
              raise Sink.new("%s warp tours not found: id=%d", self, warp_id)
            else
              nil
            end
          end

          def packet_unpacker
            return @protocol_handler.packet_unpacker
          end

          def notify_error_to_owner_tour(status, msg)
            @lock.synchronize do
              @tour_map.keys.each do |warp_id|
                tur = get_tour(warp_id)
                BayLog.debug("%s send error to owner: %s running=%s", self, tur, tur.running?)
                if tur.running?
                  begin
                    tur.res.send_error(Tour::TOUR_ID_NOCHECK, status, msg)
                  rescue Exception => e
                    BayLog.error_e(e)
                  end
                end
              end
              @tour_map.clear
            end
          end


          def end_ship()
            @docker.return_protocol_handler(@agent, @protocol_handler)
            @docker.return_ship(self)
          end

          def abort(check_id)
            check_ship_id(check_id)
            @postman.abort
          end

          def is_timeout(duration)
            if @keeping
              # warp connection never timeout in keeping
              timeout = false
            elsif @socket_timeout_sec <= 0
              timeout = false
            else
              timeout = duration >= @socket_timeout_sec
            end

            BayLog.debug("%s Warp check timeout: dur=%d, timeout=%s, keeping=%s limit=%d",
                         self, duration, timeout, @keeping, @socket_timeout_sec)
            return timeout
          end

          def inspect
            to_s
          end
        end
      end
    end
  end
end
