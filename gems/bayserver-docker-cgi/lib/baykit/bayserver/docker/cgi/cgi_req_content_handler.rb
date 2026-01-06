require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/common/postpone'
require 'baykit/bayserver/common/rudder_state_store'
require 'baykit/bayserver/train/train'
require 'baykit/bayserver/tours/req_content_handler'

require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/http_status'

module Baykit
  module BayServer
    module Docker
      module Cgi
        class CgiReqContentHandler
          include Baykit::BayServer::Tours::ReqContentHandler   # implements
          include Baykit::BayServer::Common::Postpone   # implements

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Agent::Multiplexer
          include Baykit::BayServer::Train
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Util
          include Baykit::BayServer::Common

          READ_CHUNK_SIZE = 8192

          attr :cgi_docker
          attr :tour
          attr :tour_id
          attr :available
          attr :pid
          attr :std_in_rd
          attr :std_out_rd
          attr :std_err_rd
          attr :std_out_closed
          attr :std_err_closed
          attr :last_access
          attr_accessor :multiplexer
          attr :env
          attr :buffers

          def initialize(cgi_docker, tur, env)
            @cgi_docker = cgi_docker
            @tour = tur
            @tour_id = tur.tour_id
            @env = env
            @pid = 0
            @std_in_rd = nil
            @std_out_rd = nil
            @std_err_rd = nil
            @std_out_closed = true
            @std_err_closed = true
            @buffers = []
          end

          ######################################################
          # Implements Postpone
          ######################################################
          def run
            @cgi_docker.sub_wait_count
            BayLog.info("%s challenge postponed tour", @tour, @cgi_docker.get_wait_count)
            req_start_tour
          end

          ######################################################
          # Implements ReqContentHandler
          ######################################################

          def on_read_req_content(tur, buf, start, len, &callback)
            BayLog.debug("%s CGI:onReadReqContent: len=%d", tur, len)

            if @pid != 0
              write_to_std_in(tur, buf, start, len, &callback)
            else
              # postponed
              @buffers << [buf[start, len].dup, callback]
            end
            access()
          end

          def on_end_req_content(tur)
            BayLog.trace("%s CGI:endReqContent", tur)
            access()
          end

          def on_abort_req(tur)
            BayLog.debug("%s CGI:abortReq", tur)

            if !@std_out_closed
              @multiplexer.req_close(@std_out_rd)
            end
            if !@std_err_closed
              @multiplexer.req_close(@std_err_rd)
            end

            if @pid == nil
              BayLog.warn("%s Cannot kill process (pid is null)", tur)
            else
              BayLog.debug("%s KILL PROCESS!: %d", tur, @pid)
              Process.kill('KILL', @pid)
            end

            return false  # not aborted immediately
          end

          ######################################################
          # Other methods
          ######################################################

          def req_start_tour
            if @cgi_docker.add_process_count
              BayLog.info("%s start tour: wait count=%d", @tour, @cgi_docker.get_wait_count)
              start_tour
            else
              BayLog.warn("%s Cannot start tour: wait count=%d", @tour, @cgi_docker.get_wait_count)
              agt = GrandAgent.get(@tour.ship.agent_id)
              agt.add_postpone(self)
            end
            access()
          end

          def start_tour
            @available = false

            std_in = IO.pipe()
            std_out = IO.pipe()
            std_err = IO.pipe()
            std_in[1].set_encoding("ASCII-8BIT")
            std_out[0].set_encoding("ASCII-8BIT")
            std_err[0].set_encoding("ASCII-8BIT")

            command = @cgi_docker.create_command(@env)
            BayLog.debug("%s Spawn: %s", @tour, command)
            @pid = Process.spawn(env, command, :in => std_in[0], :out => std_out[1], :err => std_err[1])
            BayLog.debug("%s created process; %s", @tour, @pid)

            std_in[0].close()
            std_out[1].close()
            std_err[1].close()

            @std_in_rd = IORudder.new(std_in[1])
            @std_out_rd = IORudder.new(std_out[0])
            @std_err_rd = IORudder.new(std_err[0])
            BayLog.debug("#{@tour} PID: #{pid}")

            @buffers.each do |pair|
              BayLog.debug("%s write postponed data: len=%d", @tour, pair[0].length)
              write_to_std_in(@tour, pair[0], 0, pair[0].length, &pair[1])
            end

            @std_out_closed = false
            @std_err_closed = false

            bufsize = 8192

            agt = GrandAgent.get(@tour.ship.agent_id)

            case(BayServer.harbor.cgi_multiplexer)
            when Harbor::MULTIPLEXER_TYPE_SPIDER
              mpx = agt.spider_multiplexer
              @std_out_rd.set_non_blocking
              @std_err_rd.set_non_blocking

            when Harbor::MULTIPLEXER_TYPE_SPIN

              def eof_checker()
                begin
                  pid = Process.wait(handler.pid,  Process::WNOHANG)
                  return pid != nil
                rescue Errno::ECHILD => e
                  BayLog.error_e(e)
                  return true
                end
              end
              mpx = agt.spin_multiplexer
              @std_out_rd.set_non_blocking
              @std_err_rd.set_non_blocking

            when Harbor::MULTIPLEXER_TYPE_TAXI
              mpx = agt.taxi_multiplexer

            when Harbor::MULTIPLEXER_TYPE_JOB
              mpx = agt.job_multiplexer

            else
              raise Sink.new();
            end

            if mpx != nil
              @multiplexer = mpx
              out_ship = CgiStdOutShip.new
              out_tp = PlainTransporter.new(agt.net_multiplexer, out_ship, false, bufsize, false)

              out_ship.init_std_out(@std_out_rd, @tour.ship.agent_id, @tour, out_tp, self)

              out_st = RudderStateStore.get_store(agt.agent_id).rent()
              out_st.init(@std_out_rd, out_tp)
              mpx.add_rudder_state(@std_out_rd, out_st)

              ship_id = out_ship.ship_id
              @tour.res.set_consume_listener do |len, resume|
                if resume
                  out_ship.resume_read(ship_id)
                end
              end

              err_ship = CgiStdErrShip.new
              err_tp = PlainTransporter.new(agt.net_multiplexer, err_ship, false, bufsize, false)
              err_ship.init_std_err(@std_err_rd, @tour.ship.agent_id, self)

              err_st = RudderStateStore.get_store(agt.agent_id).rent()
              err_st.init(@std_err_rd, err_tp)
              mpx.add_rudder_state(@std_err_rd, err_st)

              mpx.req_read(@std_out_rd)
              mpx.req_read(@std_err_rd)
            end
          end

          def std_out_closed()
            @std_out_closed = true
            if @std_out_closed && @std_err_closed
              process_finished()
            end
          end

          def std_err_closed()
            @std_err_closed = true
            if @std_out_closed && @std_err_closed
              process_finished()
            end
          end

          def access()
            @last_access = Time.now.tv_sec
          end

          def timed_out()
            if @cgi_docker.timeout_sec <= 0
              return false
            end

            duration_sec = Time.now.tv_sec - @last_access
            BayLog.debug("%s Check CGI timeout: dur=%d, timeout=%d", @tour, duration_sec, @cgi_docker.timeout_sec)
            return duration_sec > @cgi_docker.timeout_sec
          end

          def write_to_std_in(tur, buf, start, len, &callback)
            wrote_len = @std_in_rd.write(buf[start, len])
            BayLog.debug("%s CGI:onReadReqContent: wrote=%d", tur, wrote_len)
            tur.req.consumed(Tour::TOUR_ID_NOCHECK, len, &callback)
          end

          def process_finished()
            BayLog.debug("%s CGI Process finished: pid=%s", @tour, @pid)

            pid, stat = Process.wait2(@pid)
            BayLog.debug("%s CGI Process finished: pid=%s code=%s", @tour, pid, stat.exitstatus)
            agt_id = @tour.ship.agent_id

            begin
              if stat.exitstatus != 0
                # Exec failed
                BayLog.error("%s CGI Invalid exit status pid=%d code=%s", @tour, @pid, stat.exitstatus)
                @tour.res.send_error(@tour_id, HttpStatus::INTERNAL_SERVER_ERROR, "Invalid exit Status")
              else
                @tour.res.end_res_content(@tour_id)
              end
            rescue IOError => e
              BayLog.error_e(e)
            end

            @cgi_docker.sub_process_count
            if @cgi_docker.get_wait_count > 0
              BayLog.warn("agt#%d Catch up postponed process: process wait count=%d", agt_id, @cgi_docker.get_wait_count)
              agt = GrandAgent.get(agt_id)
              agt.req_catch_up
            end
          end
        end
      end
    end
  end
end
