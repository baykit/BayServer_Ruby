require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/common/read_only_ship'
require 'baykit/bayserver/util/http_status'

module Baykit
  module BayServer
    module Tours
      class SendFileShip < Baykit::BayServer::Common::ReadOnlyShip

        include Baykit::BayServer::Agent
        include Baykit::BayServer::Util

        attr :file_wrote_len
        attr :tour
        attr :tour_id

        def initialize
          @file_wrote_len = 0
          @tour = nil
          @tour_id = 0
        end

        def init(rd, tp, tur)
          super(tur.ship.agent_id, rd, tp)
          @tour = tur
          @tour_id = tur.tour_id
        end

        def to_s
          return "agt#" + @agent_id.to_s + " send_file#" + @ship_id.to_s + "/" + @object_id.to_s
        end

        ######################################################
        # Implements Reusable
        ######################################################

        def reset
          super
          @file_wrote_len = 0
          @tour_id = 0
          @tour = nil
        end

        ######################################################
        # Implements ReadOnlyShip
        ######################################################

        def notify_read(buf)
          @file_wrote_len += buf.length
          BayLog.debug("%s read file %d bytes: total=%d", self, buf.length, @file_wrote_len)

          begin
            available = @tour.res.send_res_content(@tour_id, buf, 0, buf.length)
            if available
              return NextSocketAction::CONTINUE
            else
              return NextSocketAction::SUSPEND
            end
          rescue IOError => e
            notify_error(e)
            return NextSocketAction::CLOSE
          end
        end

        def notify_error(e)
          BayLog.debug_e(e, "%s Error notified", self)
          begin
            @tour.res.send_error(@tour_id, HttpStatus::INTERNAL_SERVER_ERROR, nil, e)
          rescue IOError => ex
            BayLog.debug_e(ex)
          end
        end

        def notify_eof
          BayLog.debug("%s EOF", self)
          begin
            @tour.res.end_res_content(@tour_id)
          rescue IOError => e
            BayLog.debug_e(e)
          end
          return NextSocketAction::CLOSE
        end

        def notify_close
          # Return to the per-agent SendFileShipStore so the next file
          # request reuses this instance instead of allocating fresh.
          # Skip if we never got a real agent_id (= ship was rented but
          # init didn't run, e.g. error on the rent path).
          if @initialized && @agent_id && @agent_id > 0
            require 'baykit/bayserver/tours/send_file_ship_store'
            store = Baykit::BayServer::Tours::SendFileShipStore.get_store(@agent_id)
            store.Return(self) if store && store.active_list.include?(self)
          end
        end

        def check_timeout(duration_sec)
          return false
        end

      end
    end
  end
end
