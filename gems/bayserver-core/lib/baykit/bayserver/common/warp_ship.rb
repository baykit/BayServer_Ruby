require 'baykit/bayserver/util/counter'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/common/warp_ship'

module Baykit
  module BayServer
      module Common
        class WarpShip < Baykit::BayServer::Ships::Ship
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Ships
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Util

          attr :tour_map
          attr :docker

          attr :protocol_handler
          attr_accessor :connected
          attr :socket_timeout_sec
          attr :lock
          attr :cmd_buf

          def initialize()
            super
            @docker = nil
            @socket_timeout_sec = nil
            @tour_map = {}
            @lock = Mutex.new()
            @connected = false
            @cmd_buf = []
          end

          def init_warp(rd, agt_id, tp, dkr, proto_hnd)
            init(agt_id, rd, tp)
            @docker = dkr
            @socket_timeout_sec = @docker.timeout_sec >= 0 ? @docker.timeout_sec : BayServer.harbor.socket_timeout_sec
            @protocol_handler = proto_hnd
            @protocol_handler.init(self)
          end

          def to_s()
            protocol = ""
            if @protocol_handler != nil
              protocol = "[#{@protocol_handler.protocol}]"
            end
            return "agt##{agent_id} wsip##{@ship_id}/#{@object_id}[#{protocol}]"
          end

          def inspect
            to_s
          end

          #########################################
          # Implements Reusable
          #########################################

          def reset()
            super
            if !@tour_map.empty?
              BayLog.error("BUG: Some tours is active: %s", @tour_map)
            end
            @connected = false
            @tour_map = {}
            @cmd_buf = []
          end

          #########################################
          # Implements Ship
          #########################################
          def notify_handshake_done(proto)
            @protocol_handler.verify_protocol(protocol)
            NextSocketAction::CONTINUE
          end

          def notify_connect()
            @connected = true
            @tour_map.values.each do |pair|
              tur = pair[1]
              tur.check_tour_id pair[0]
              WarpData.get(tur).start
            end
            NextSocketAction::CONTINUE
          end

          def notify_read(buf)
            return @protocol_handler.bytes_received(buf)
          end

          def notify_eof()
            BayLog.debug("%s EOF detected", self)

            if @tour_map.empty?
              BayLog.debug("%s No warp tours. only close", self)
              return NextSocketAction::CLOSE
            end

            @tour_map.each do |warp_id, pair|
              tur = pair[1]
              tur.check_tour_id pair[0]

              begin
                if !tur.res.header_sent
                  BayLog.debug("%s Send ServiceUnavailable: tur=%s", self, tur)
                  tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::SERVICE_UNAVAILABLE, "Server closed on reading headers")
                else
                  # NOT treat EOF as Error
                  BayLog.debug("%s EOF is not an error: tur=%s", self, tur)
                  tur.res.end_res_content(Tour::TOUR_ID_NOCHECK)
                end
              rescue IOError => e
                BayLog::debug_e(e)
              end
            end

            @tour_map.clear()
            return NextSocketAction::CLOSE
          end

          def notify_error(e)
            BayLog.error_e(e, "notify_error")
          end

          def notify_protocol_error(e)
            BayLog.error_e(e)
            notify_error_to_owner_tour(HttpStatus::SERVICE_UNAVAILABLE, e.message)
            true
          end

          def notify_close
            BayLog.debug("%s notifyClose", self)
            notify_error_to_owner_tour(HttpStatus::SERVICE_UNAVAILABLE, "#{self} server closed")
            end_ship()
          end

          def check_timeout(duration_sec)
            if is_timeout(duration_sec)
              notify_error_to_owner_tour(HttpStatus::GATEWAY_TIMEOUT, "#{self} server timeout")
              true
            else
              false
            end
          end

          ################################
          # Other methods
          ################################

          def warp_handler
            return @protocol_handler.command_handler
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
            w_hnd.send_res_headers(tur)

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
            @docker.keep(self)
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
                else
                  tur.res.end_res_content(Tour::TOUR_ID_NOCHECK)
                end
              end
              @tour_map.clear
            end
          end


          def end_ship()
            @docker.on_end_ship(self)
          end

          def abort(check_id)
            check_ship_id(check_id)
            @transporter.req_close(@rudder)
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

          def post(cmd, &listener)
            if !@connected
              @cmd_buf << [cmd, listener]
            else
              if cmd == nil
                listener.call()
              else
                @protocol_handler.post(cmd, &listener)
              end
            end
          end
          def flush()
              @cmd_buf.each do | cmd_and_lis |
                cmd = cmd_and_lis[0]
                lis = cmd_and_lis[1]
                if cmd == nil
                  lis.call()
                else
                  @protocol_handler.post(cmd, &lis)
                end
              end
              @cmd_buf = []
          end
        end
      end
  end
end
