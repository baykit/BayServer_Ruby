require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/protocol/packet_store'
require 'baykit/bayserver/docker/http/h1/h1_packet_unpacker'
require 'baykit/bayserver/docker/http/h1/h1_command_unpacker'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/http_status'


module Baykit
  module BayServer
    module Docker
      module Terminal
        #
        # Send data of hijacked response
        #
        class HijackedDataSender
          include Baykit::BayServer::Agent::NonBlockingHandler::ChannelListener  # implements
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Docker::Http::H1

          attr :tour
          attr :tour_id
          attr :fully

          attr :file_wrote_len
          attr :file_buf_list
          attr :cur_file_idx
          attr :read_buf_size
          attr :cur_file_idx
          attr :pipe_io

          attr :packet_store
          attr :packet_unpacker
          attr :command_unpacker

          DEFAULT_FREAD_BUF_SIZE = 8192

          def initialize(tur, fully)
            @tour = tur
            @tour_id = @tour.tour_id
            @fully = fully
            @file_buf_list = []
            @read_buf_size = tour.ship.protocol_handler.max_res_packet_data_size

            if @fully
              @packet_store = PacketStore.new(tur.ship, H1PacketFactory.new)
              @command_unpacker = H1CommandUnPacker.new(self, false)
              @packet_unpacker = H1PacketUnPacker.new(@command_unpacker, @packet_store)
            end
            reset
          end

          def reset
            @file_wrote_len = 0
            @cur_file_idx = -1
          end

          def ship
            @tour.ship
          end

          def on_readable(chk_fd)
            BayLog.debug "#{self} Hijack Readable"
            check_socket(chk_fd)

            buf = new_file_buffer
            begin
              @pipe_io.read_nonblock(@read_buf_size, buf)
            rescue EOFError => e
              BayLog.debug "#{self} Hijack EOF"
              @tour.res.end_content(@tour_id)
              return NextSocketAction::CLOSE
            end

            @file_wrote_len += buf.length

            BayLog.debug "#{self} read hijack #{buf.length} bytes: total=#{@file_wrote_len}"

            if @fully
              return @packet_unpacker.bytes_received(buf)
            else
              available = @tour.res.send_content(@tour_id, buf, 0, buf.length)
              if !available
                NextSocketAction::SUSPEND
              else
                NextSocketAction::CONTINUE
              end
            end

          end

          def check_timeout(chk_fd, duration)
            BayLog.debug "#{self} Hijack timeout(Ignore)"
          end

          def on_error(chk_fd, e)
            BayLog.debug "#{self} Hijack Error"
            check_socket(chk_fd)

            BayLog.error_e e
          end

          def on_closed(chk_fd)
            BayLog.debug "#{self} Hijack Closed(Ignore)"
            check_socket(chk_fd)
          end


          def send_pipe_data(io)
            BayLog.debug("#{self} Send hijacked data #{io.inspect}")
            @pipe_io = io
            @file_wrote_len = 0
            @tour.ship.agent.non_blocking_handler.ask_to_read(@pipe_io)
          end

          # Implements H1CommandHandler
          # Fully hijacked mode
          def handle_header(cmd)
            cmd.headers.each do |nv|
              @tour.res.headers.add(nv[0], nv[1])
            end

            @tour.res.headers.status = cmd.status != nil ? cmd.status : HttpStatus::OK
            @tour.send_headers(@tour_id)

            return NextSocketAction::CONTINUE
          end

          # Implements H1CommandHandler
          # Fully hijacked mode
          def handle_content(cmd)
            available = @tour.res.send_content(@tour_id, cmd.buf, cmd.start, cmd.len)
            if !available
              NextSocketAction::SUSPEND
            else
              NextSocketAction::CONTINUE
            end
          end

          def resume
            BayLog.debug("#{self} resume")
            @tour.ship.agent.non_blocking_handler.ask_to_read(@pipe_io)
          end

          def to_s
            "hijack[#{@pipe_io.inspect}]"
          end

          private
          def check_socket(chk_fd)
            if chk_fd != @pipe_io
              raise RuntimeError.new("BUG: Invalid hijacked data sender instance (file was returned?): #{chk_fd}")
            end
          end

          def new_file_buffer
            @cur_file_idx += 1
            if @file_buf_list.length == @cur_file_idx
              @file_buf_list << StringUtil.alloc(@read_buf_size)
            end
            @file_buf_list[@cur_file_idx]
          end
        end
      end
    end
  end
end

