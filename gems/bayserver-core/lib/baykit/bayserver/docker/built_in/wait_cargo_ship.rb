require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/http_exception'
require 'baykit/bayserver/sink'
require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/common/read_only_ship'
require 'baykit/bayserver/tours/content_consume_listener'
require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/util/http_status'

module Baykit
  module BayServer
    module Docker
      module BuiltIn
        class WaitCargoShip < Baykit::BayServer::Common::ReadOnlyShip

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Tours

          attr :cargo
          attr :club
          attr :tour
          attr :tour_id

          def initialize()
            @cargo = nil
            @club = nil
            @tour = nil
            @tour_id = 0
          end

          def init(rd, tp, tur, cgo, clb)
            super(tur.ship.agent_id, rd, tp)
            @tour = tur
            @tour_id = tur.tour_id
            @cargo = cgo
            @club = clb
          end

          def to_s
            return "agt#" + @agent_id.to_s + " wait_file#" + @ship_id.to_s + "/" + @object_id.to_s
          end

          ######################################################
          # Implements Reusable
          ######################################################

          def reset
            super
            @tour_id = 0
            @tour = nil
          end

          ######################################################
          # Implements ReadOnlyShip
          ######################################################

          # Waked up by pipe
          def notify_read(buf)

            BayLog.debug("%s cargo load completed", @tour)

            begin
              if @cargo.exceeded?
                BayLog.debug("%s cargo exceeded", @tour)
                @club.arrive(@tour)
              else
                @tour.res.set_consume_listener(&ContentConsumeListener::DEV_NULL)
                send_cargo_on_board
              end
            rescue HttpException => e
              begin
                @tour.res.send_error(Tour::TOUR_ID_NOCHECK, e.status, e.message)
              rescue IOError => ex
                notify_error(ex)
                return NextSocketAction::CLOSE
              end
            end

            @cargo.release_rudder(@rudder)

            return NextSocketAction::CONTINUE
          end

          def notify_error(e)
            BayLog.debug_e(e, "%s Error notified", @tour)
            begin
              @tour.res.send_error(@tour_id, HttpStatus::INTERNAL_SERVER_ERROR, nil, e)
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

          private

          def send_cargo_on_board
            @tour.res.set_consume_listener(&ContentConsumeListener::DEV_NULL)
            @cargo.headers.copy_to(@tour.res.headers)
            begin
              @tour.res.send_headers(Tour::TOUR_ID_NOCHECK)
              @tour.res.send_res_content(Tour::TOUR_ID_NOCHECK, @cargo.content, 0, @cargo.length)
              @tour.res.end_res_content(Tour::TOUR_ID_NOCHECK)
            rescue IOError => e
              BayLog.error_e(e)
              raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR, @cargo.path)
            end
          end

        end
      end
    end
  end
end
