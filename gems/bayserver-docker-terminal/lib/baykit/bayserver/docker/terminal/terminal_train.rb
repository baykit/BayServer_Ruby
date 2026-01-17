require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/common/read_only_ship'
require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/train/train'
require 'baykit/bayserver/train/train_runner'
require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/tours/req_content_handler'

require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/http_status'

require 'baykit/bayserver/docker/terminal/hijackers_ship'

module Baykit
  module BayServer
    module Docker
      module Terminal
        class TerminalTrain < Baykit::BayServer::Train::Train
          include Baykit::BayServer::Tours::ReqContentHandler   # implements

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Agent::Multiplexer
          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Util
          include Baykit::BayServer::Train
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Common

          attr :terminal_docker
          attr :tour
          attr :tour_id
          attr :app
          attr :env

          attr :req_available
          attr :lock
          attr :tmpfile
          attr :req_cont

          def initialize(terminal_docker, tur, app, env)
            BayLog.debug "%s New Rack Train", tur
            @terminal_docker = terminal_docker
            @tour = tur
            @tour_id = tur.tour_id
            @app = app
            @env = env
            @available = false
            @tmpfile = nil
            @req_cont = nil

            @lock = Mutex.new
          end

          def start_tour()
            @tour.req.set_content_handler(self)
            @tmpfile = nil

            if @env["CONTENT_LENGTH"]
              req_cont_len = @env["CONTENT_LENGTH"].to_i
            else
              req_cont_len = 0
            end

            if req_cont_len <= @terminal_docker.post_cache_threshold
              # Cache content in memory
              @req_cont = StringUtil.alloc(0)
            else
              # Content save on disk
              @tmpfile = Tempfile.new("terminal_upload")
              @tmpfile.binmode
            end

          end

          def depart

            begin
              if @tour.req.method.casecmp?("post")
                BayLog.debug("%s Terminal: posted: content-length: %s", @tour, @env["CONTENT_LENGTH"])
              end


              if BayServer.harbor.trace_header
                @env.keys.each do |key|
                  value = @env[key]
                  BayLog.info("%s Terminal: env:%s=%s", @tour, key, value)
                end
              end

              status, headers, body = @app.call(@env)

              # Hijack check
              pip = @env[TerminalDocker::RACK_TERMINAL_PIPE]

              if pip != nil
                # Fully hijacked (Do nothing)
                BayLog.debug("%s Tour is fully hijacked", @tour)

              else
                @tour.res.headers.status = status

                hijack = nil
                headers.each do | key, value |
                  if key == Rack::RACK_HIJACK
                    hijack = value
                  else
                    @tour.res.headers.add key, value
                  end
                end

                # Send headers
                @tour.res.send_headers @tour_id

                if hijack != nil
                  # Partially hijacked
                  BayLog.debug("%s Tour is partially hijacked", @tour)
                  agt = GrandAgent.get(@tour.ship.agent_id)
                  mpx = agt.net_multiplexer
                  pip = IO.pipe
                  rd_read = IORudder.new(pip[0])
                  sip = HijackersShip.new()
                  bufsize = @tour.ship.protocol_handler.max_res_packet_data_size()
                  tp = PlainTransporter.new(mpx, sip, false, bufsize, false)

                  sip.init(@tour, rd_read, tp)
                  sid = sip.ship_id

                  @tour.res.set_consume_listener do |len, resume|
                    if resume
                      sip.resume_read(sid)
                    end
                  end

                  st = RudderStateStore.get_store(@tour.ship.agent_id).rent
                  st.init(rd_read, tp)
                  mpx.add_rudder_state(rd_read, st)
                  mpx.req_read(rd_read)

                  hijack.call pip[1]

                else
                  # Not hijacked

                  # Setup consume listener
                  @tour.res.set_consume_listener() do |len, resume|
                    if(resume)
                      @available = true
                    end
                  end

                  # Send contents
                  body.each do | str |
                    bstr = StringUtil.to_bytes(str)
                    BayLog.trace("%s TerminalTask: read body: len=%d", @tour, bstr.length)
                    @available = @tour.res.send_res_content(@tour_id, bstr, 0, bstr.length)
                    while !@available
                      sleep 0.1
                    end
                  end

                  @tour.res.end_res_content(@tour_id)

                end
              end
            rescue HttpException => e
              raise e
            rescue => e
              BayLog.error_e e
              raise HttpException.new HttpStatus::INTERNAL_SERVER_ERROR, "Terminal error"
            ensure
              if @tmpfile
                @tmpfile.close()
              end
            end
          end

          def on_read_req_content(tur, buf, start, len, &lis)
            BayLog.trace("%s TerminalTask:onReadContent: len=%d", @tour, len)

            if @req_cont != nil
              # Cache content in memory
              @req_cont << buf[start, len]
            else
              # Content save on disk
              @tmpfile.write(buf[start, len])
            end

            tur.req.consumed(Tour::TOUR_ID_NOCHECK, len, &lis)
            true
          end

          def on_end_req_content(tur)
            BayLog.trace("%s TerminalTask:endContent", @tour)

            if @req_cont != nil
              # Cache content in memory
              rack_input = StringIO.new(@req_cont)
            else
              # Content save on disk
              @tmpfile.rewind()
              rack_input = @tmpfile
            end
            env[Rack::RACK_INPUT] = rack_input

            if !TrainRunner.post(tur.ship.agent_id, self)
              raise HttpException.new(HttpStatus::SERVICE_UNAVAILABLE, "TrainRunner is busy")
            end
          end

          def on_abort_req(tur)
            BayLog.trace("%s TerminalTask:abort", @tour)
            if @tmpfile
              @tmpfile.close()
              @tmpfile = nil
            end
            return false
          end

          def on_timer
            BayLog.debug("%s TerminalTask:timer", @tour)
          end

          def inspect
            "TerminalTask #{@tour}"
          end
        end
      end
    end
  end
end
