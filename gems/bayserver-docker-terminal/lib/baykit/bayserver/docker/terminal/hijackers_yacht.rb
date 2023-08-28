require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/watercraft/yacht'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/reusable'

require 'baykit/bayserver/docker/http/h1/h1_command_handler'

module Baykit
  module BayServer
    module Docker
      module Terminal
        class HijackersYacht < Baykit::BayServer::WaterCraft::Yacht
          include Baykit::BayServer::Docker::Http::H1::H1CommandHandler   # implements

          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Docker::Http::H1

          attr :tour
          attr :tour_id

          attr :file_wrote_len
          attr :pipe_io

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

          def init(tur, io, tp)
            init_yacht()
            @tour = tur
            @tour_id = @tour.tour_id

            tur.res.set_consume_listener do |len, resume|
              if resume
                tp.open_valve();
              end
            end
            @pipe_io = io
            @file_wrote_len = 0
            @tour.ship.agent.non_blocking_handler.ask_to_read(@pipe_io)
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

            available = @tour.res.send_content(@tour_id, buf, 0, buf.length)
            if !available
              return NextSocketAction::SUSPEND
            else
              return NextSocketAction::CONTINUE
            end
          end

          def notify_eof()
            BayLog.debug "#{self} Hijack EOF"
            @tour.res.end_content(@tour_id)
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

