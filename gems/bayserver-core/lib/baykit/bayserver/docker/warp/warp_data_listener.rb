require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/agent/transporter/data_listener'
require 'baykit/bayserver/docker/warp/warp_ship'
require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/util/counter'
require 'baykit/bayserver/util/http_status'

module Baykit
  module BayServer
    module Docker
      module Warp
        class WarpDataListener

          include Baykit::BayServer::Agent::Transporter::DataListener   # implements

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Util
          include Baykit::BayServer::Tours

          attr :ship

          def initialize(sip)
            @ship = sip
          end

          def to_s()
            return @ship.to_s
          end

          ######################################################
          # Implements DataListener
          ######################################################

          def notify_handshake_done(protocol)
            @ship.protocol_handler.verify_protocol(protocol)

            #  Send pending packet
            @ship.agent.non_blocking_handler.ask_to_write(@ship.socket)
            NextSocketAction::CONTINUE
          end

          def notify_connect
            @ship.connected = true
            @ship.tour_map.values.each do |pair|
              tur = pair[1]
              tur.check_tour_id pair[0]
              WarpData.get(tur).start
            end
            NextSocketAction::CONTINUE
          end

          def notify_read(buf, adr)
            return @ship.protocol_handler.bytes_received(buf)
          end

          def notify_eof
            BayLog.debug("%s EOF detected", self)

            if @ship.tour_map.empty?
              BayLog.debug("%s No warp tours. only close", self)
              return NextSocketAction::CLOSE
            end

            @ship.tour_map.keys.each do |warp_id|
              pair = @ship.tour_map[warp_id]
              tur = pair[1]
              tur.check_tour_id pair[0]

              begin
                if !tur.res.header_sent
                  BayLog.debug("%s Send ServiceUnavailable: tur=%s", self, tur)
                  tur.res.send_error(Tour::TOUR_ID_NOCHECK, HttpStatus::SERVICE_UNAVAILABLE, "Server closed on reading headers")
                else
                  # NOT treat EOF as Error
                  BayLog.debug("%s EOF is not an error: tur=%s", self, tur)
                  tur.res.end_content(Tour::TOUR_ID_NOCHECK)
                end
              rescue IOError => e
                BayLog::debug_e(e)
              end
            end

            @ship.tour_map.clear()
            return NextSocketAction::CLOSE
          end

          def notify_protocol_error(err)
            BayLog.error_e(err)
            self.ship.notify_error_to_owner_tour(HttpStatus::SERVICE_UNAVAILABLE, err.message)
            true
          end

          def check_timeout(duration_sec)
            if @ship.is_timeout(duration_sec)
              self.ship.notify_error_to_owner_tour(HttpStatus::GATEWAY_TIMEOUT, "#{self} server timeout")
              true
            else
              false
            end
          end

          def notify_close()
            BayLog.debug("%s notifyClose", self)
            self.ship.notify_error_to_owner_tour(HttpStatus::SERVICE_UNAVAILABLE, "#{self} server closed")
            self.ship.end_ship()
          end

        end
      end
    end
  end
end
