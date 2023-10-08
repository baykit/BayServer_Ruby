require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/watercraft/yacht'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Docker
      module Cgi
        class CgiStdErrYacht < Baykit::BayServer::WaterCraft::Yacht

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Util

          attr :tour
          attr :tour_id
          attr :timeout_sec

          def initialize
            super
            reset()
          end

          def to_s()
            return "CGIErrYat##{@yacht_id}/#{@object_id} tour=#{@tour} id=#{@tour_id}";
          end

          ######################################################
          # implements Reusable
          ######################################################

          def reset()
            @tour = nil
            @tour_id = 0
            @timeout_sec = 0
          end

          ######################################################
          # implements Yacht
          ######################################################

          def notify_read(buf, adr)

            BayLog.debug("%s CGI StdErr %d bytesd", self, buf.length)
            if(buf.length() > 0)
              BayLog.error("CGI Stderr: %s", buf)
            end

            return NextSocketAction::CONTINUE;

          end

          def notify_eof()
            BayLog.debug("%s stderr EOF\\(^o^)/", @tour)
            return NextSocketAction::CLOSE
          end

          def notify_close()
            BayLog.debug("%s stderr notifyClose", @tour)
            @tour.req.content_handler.std_err_closed()
          end

          def check_timeout(duration_sec)
            BayLog.debug("%s stderr Check timeout: dur=%d, timeout=%d", @tour, duration_sec, @timeout_sec);
            if @timeout_sec <= 0
              BayLog.debug("%s invalid timeout check", @tour)
              return false
            else
              return duration_sec > @timeout_sec
            end

          end

          ######################################################
          # Custom methods
          ######################################################

          def init(tur, timeout_sec)
            init_yacht()
            @tour = tur
            @tour_id = tur.tour_id
            @timeout_sec = timeout_sec
          end
        end
      end
    end
  end
end


