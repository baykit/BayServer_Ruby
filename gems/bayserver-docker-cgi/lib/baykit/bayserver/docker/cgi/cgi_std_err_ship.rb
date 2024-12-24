require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/common/read_only_ship'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Docker
      module Cgi
        class CgiStdErrShip < Baykit::BayServer::Common::ReadOnlyShip

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Util

          attr :handler

          def initialize
            super
            reset()
          end

          def init_std_err(rd, agt_id, handler)
            init(agt_id, rd, nil)
            @handler = handler
          end

          def to_s()
            return "agt#{@agent_id} err_ship#{@ship_id}/#{@object_id}";
          end

          ######################################################
          # implements Reusable
          ######################################################

          def reset()
            super
            @handler = nil
          end

          ######################################################
          # implements ReadOnlyShip
          ######################################################

          def notify_read(buf)

            BayLog.debug("%s CGI StdErr %d bytesd", self, buf.length)
            if(buf.length() > 0)
              BayLog.error("CGI Stderr: %s", buf)
            end

            return NextSocketAction::CONTINUE;

          end

          def notify_error(e)
            BayLog.debug_e(e)
          end

          def notify_eof()
            BayLog.debug("%s CGI stderr EOF\\(^o^)/ tur=%s", self, @tour)
            return NextSocketAction::CLOSE
          end

          def notify_close()
            BayLog.debug("%s CGI stderr notifyClose tur=%s", self, @tour)
            @handler.std_err_closed()
          end

          def check_timeout(duration_sec)
            BayLog.debug("%s stderr Check timeout: tur=%s dur=%d", self, @tour, duration_sec)
            return @handler.timed_out()
          end

          ######################################################
          # Custom methods
          ######################################################

        end
      end
    end
  end
end


