require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/common/read_only_ship'

module Baykit
  module BayServer
    module Docker
      module SendFile
        class WaitFileShip < Baykit::BayServer::Common::ReadOnlyShip

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Tours

          attr :file_content
          attr :handler

          attr :tour
          attr :tour_id
          def initialize()
            @file_content = nil
            @handler = nil
          end

          def init(rd, tp, tur, file_content, handler)
            super(tur.ship.agent_id, rd, tp)
            @tour = tur
            @tour_id = tur.tour_id
            @file_content = file_content
            @handler = handler
          end

          def to_s
            return "agt#" + @agent_id.to_s + " wait_file#" + @ship_id.to_s + "/" + @object_id.to_s
          end

          ######################################################
          # Implements Reusable
          ######################################################

          def reset
            super
            @file_content = nil
            @tour_id = 0
            @tour = nil
          end

          ######################################################
          # Implements ReadOnlyShip
          ######################################################

          def notify_read(buf)

            BayLog.debug("%s file read completed", self)

            begin
              @handler.send_file_from_cache
            rescue HttpException => e
              begin
                @tour.res.send_error(Tour::TOUR_ID_NOCHECK, e.status, e.message)
                rescue IOError => ex
                  notify_error(ex)
                  return NextSocketAction::CLOSE
              end
            end

            return NextSocketAction::CONTINUE
          end

          def notify_error(e)
            BayLog.debug_e(e, "%s Error notified", self)
            begin
              @tour.res.send_error(@tour_id, HttpStatus.INTERNAL_SERVER_ERROR, null, e)
            rescue IOError => ex
              BayLog.debug_e(ex)
            end
          end

          def notify_eof()
            raise Sink.new
          end

          def notify_close
          end

          def check_timeout(duration_sec)
            return false
          end

        end
      end
    end
  end
end
