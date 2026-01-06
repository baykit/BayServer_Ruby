require 'baykit/bayserver/common/read_only_ship'

module Baykit
  module BayServer
    module Docker
      module SendFile
        class SendFileShip < Baykit::BayServer::Common::ReadOnlyShip
          include Baykit::BayServer::Tours::ReqContentHandler   # implements

          attr :file_wrote_len

          attr :file_content
          attr :tour
          attr :tour_id

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Agent::Multiplexer
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Rudders

          attr :path
          attr :abortable

          def init(rd, tp, tur, file_content)
            super(tur.ship.agent_id, rd, tp)
            @file_wrote_len = 0
            @tour = tur
            @tour_id = tur.tour_id
            @file_content = file_content
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
          # Implements ReqContentHandler
          ######################################################

          def notify_read(buf)
            @file_wrote_len += buf.length
            BayLog.debug("%s read file %d bytes: total=%d", self, buf.length, @file_wrote_len)

            begin
              available = @tour.res.send_res_content(@tour_id, buf, 0, buf.length)

              if @file_content != nil
                BayLog.debug("buf=%s target=%s", buf, @file_content.content)
                @file_content.content << buf
                @file_content.bytes_loaded += buf.length
              end

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
              BayLog.debug_e(ex)
            end
            return NextSocketAction::CLOSE
          end

          def notify_close
            BayLog.debug("%s Close", self)
          end

          def check_timeout(duration_sec)
            return false
          end
        end
      end
    end
  end
end
