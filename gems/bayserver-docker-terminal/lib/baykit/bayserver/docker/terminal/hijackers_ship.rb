require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/reusable'

require 'baykit/bayserver/docker/http/h1/h1_command_handler'

module Baykit
  module BayServer
    module Docker
      module Terminal
        class HijackersShip < Baykit::BayServer::Common::ReadOnlyShip
          include Baykit::BayServer::Docker::Http::H1::H1CommandHandler   # implements

          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Docker::Http::H1

          attr :tour
          attr :tour_id

          attr :file_wrote_len

          attr :packet_store
          attr :packet_unpacker
          attr :command_unpacker

          def initialize
            super
            reset()
          end

          def to_s()
            return "hijack##{@yacht_id}/#{@object_id} tour=#{@tour} id=#{@tour_id}";
          end

          ######################################################
          # Init method
          ######################################################
          def init(tur, rd, tp)
            super(tur.ship.agent_id, rd, tp)

            @tour = tur
            @tour_id = tur.tour_id
            @file_wrote_len = 0
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

          def notify_read(buf)
            @file_wrote_len += buf.length

            BayLog.debug "#{self} read hijack #{buf.length} bytes: total=#{@file_wrote_len}"

            available = @tour.res.send_res_content(@tour_id, buf, 0, buf.length)
            if !available
              return NextSocketAction::SUSPEND
            else
              return NextSocketAction::CONTINUE
            end
          end

          def notify_error(e)
            BayLog.debug_e(e, "%s Hijack Error", self)
            begin
              @tour.res.send_error(@tour_id, HttpStatus::INTERNAL_SERVER_ERROR, nil, e)
            rescue IOError => ex
              BayLog.debug_e(ex)
            end
          end

          def notify_eof()
            BayLog.debug "#{self} Hijack EOF"
            BayLog.debug("%s EOF", self)
            begin
              @tour.res.end_res_content(@tour_id)
            rescue IOError => e
              BayLog.debug_e(ex)
            end
            return NextSocketAction::CLOSE
          end

          def notify_close()
            BayLog.debug("%s Hijack Closed(Ignore)", self)
          end

          def check_timeout(duration)
            BayLog.debug("%s Hijack timeout(Ignore)", self)
          end

        end
      end
    end
  end
end

