require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/watercraft/yacht'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/reusable'

require 'baykit/bayserver/docker/terminal/hijackers_yacht'

require 'baykit/bayserver/docker/http/h1/h1_command_handler'

module Baykit
  module BayServer
    module Docker
      module Terminal
        class FullyHijackersYacht < HijackersYacht
          include Baykit::BayServer::Docker::Http::H1::H1CommandHandler   # implements

          include Baykit::BayServer::Util
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Docker::Http::H1

          STATE_READ_HEADER = 1
          STATE_READ_CONTENT = 2
          STATE_FINISHED = 3

          attr :state
          attr :packet_store
          attr :packet_unpacker
          attr :command_unpacker

          def initialize
            super
          end

          ######################################################
          # Init method
          ######################################################
          #
          def init(tur, io, tp)
            super
            @packet_store = PacketStore.new(tur.ship, H1PacketFactory.new)
            @command_unpacker = H1CommandUnPacker.new(self, false)
            @packet_unpacker = H1PacketUnPacker.new(@command_unpacker, @packet_store)
          end

          ######################################################
          # implements Reusable
          ######################################################

          def reset()
            super
            @state = STATE_FINISHED
          end

          ######################################################
          # implements Yacht
          ######################################################

          # Override
          def notify_read(buf, adr)
            @file_wrote_len += buf.length

            BayLog.debug "#{self} read hijack #{buf.length} bytes: total=#{@file_wrote_len}"

            return @packet_unpacker.bytes_received(buf)

          end


          ######################################################
          # Implements H1CommandHandler
          ######################################################

          def handle_header(cmd)
            if @state == STATE_FINISHED
              change_state(STATE_READ_HEADER)
            end

            if @state != STATE_READ_HEADER
              raise ProtocolException("Header command not expected: state=%d", @state)
            end

            if BayServer.harbor.trace_header?
              BayLog.info("%s hijack: resStatus: %d", self, cmd.status)
            end

            cmd.headers.each do |nv|
              @tour.res.headers.add(nv[0], nv[1])
              if BayServer.harbor.trace_header?
                BayLog.info("%s hijack: resHeader: %s=%s", self, nv[0], nv[1]);
              end
            end

            @tour.res.headers.status = cmd.status != nil ? cmd.status : HttpStatus::OK
            @tour.res.send_headers(@tour_id)

            res_cont_len = @tour.res.headers.content_length
            BayLog.debug("%s contLen in header: %d", self, res_cont_len)

            if res_cont_len == 0 || cmd.status == HttpStatus::NOT_MODIFIED
              end_res_content(@tour)
            else
              change_state(STATE_READ_CONTENT)
              sid = @tour.ship.id()
              @tour.res.set_consume_listener do |len, resume|
                if resume
                  @tour.ship.resume(sid)
                end
              end
            end
            return NextSocketAction::CONTINUE
          end

          def handle_content(cmd)

            if @state != STATE_READ_CONTENT
              raise ProtocolException.new("Content command not expected")
            end

            available = @tour.res.send_content(@tour_id, cmd.buf, cmd.start, cmd.len)
            if @tour.res.bytes_posted == @tour.res.bytes_limit
              end_res_content(@tour)
              return NextSocketAction::CONTINUE
            elsif !available
              return NextSocketAction::SUSPEND
            else
              NextSocketAction::CONTINUE
            end
          end

          def handle_end_content(cmd)
            # never called
            raise Sink.new()
          end

          def finished()
            return @state == STATE_FINISHED
          end


          private

          def end_res_content(tur)
            tur.res.end_content(Tour::TOUR_ID_NOCHECK)
            reset()
          end

          def change_state(new_state)
            @state = new_state
          end
        end
      end
    end
  end
end

