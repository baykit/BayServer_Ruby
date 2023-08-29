require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/watercraft/yacht'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Tours
      class SendFileYacht < Baykit::BayServer::WaterCraft::Yacht

        include Baykit::BayServer::Agent
        include Baykit::BayServer::Util

        attr :tour
        attr :tour_id

        attr :file_name
        attr :file_len
        attr :file_wrote_len

        def initialize
          super
          reset()
        end

        def to_s()
          return "filyt##{@yacht_id}/#{@object_id} tour=#{@tour} id=#{@tour_id}";
        end

        ######################################################
        # implements Reusable
        ######################################################

        def reset()
          @file_wrote_len = 0
          @file_len = 0
          @tour = nil
          @tour_id = 0
        end

        ######################################################
        # implements Yacht
        ######################################################

        def notify_read(buf, adr)
          @file_wrote_len += buf.length
          BayLog.trace("%s read file %d bytes: total=%d/%d", self, buf.length, @file_wrote_len, @file_len)
          available = @tour.res.send_content(@tour_id, buf, 0, buf.length)

          if available
            return NextSocketAction::CONTINUE;
          else
            return NextSocketAction::SUSPEND;
          end

        end

        def notify_eof()
          BayLog.trace("%s EOF(^o^) %s", self, @file_name)
          @tour.res.end_content(@tour_id)
          return NextSocketAction::CLOSE
        end

        def notify_close()
          BayLog.trace("File closed: %s", @file_name)
        end

        def check_timeout(duration)
          BayLog.trace("Check timeout: %s", @file_name)
        end

        ######################################################
        # Custom methods
        ######################################################

        def init(tur, file_name, tp)
          init_yacht()
          @tour = tur
          @tour_id = tur.id()
          @file_name = file_name
          @file_len = File.size(file_name)
          #file = File.open(file_name, "rb")
          tur.res.set_consume_listener do |len, resume|
            if resume
              tp.open_valve();
            end
          end
        end
      end
    end
  end
end

