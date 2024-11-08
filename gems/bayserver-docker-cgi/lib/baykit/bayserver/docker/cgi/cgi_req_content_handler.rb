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

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Train
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Util

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

          def initialize(cgi_docker, tur)
            @cgi_docker = cgi_docker
            @tour = tur
            @tour_id = tur.tour_id
            @std_out_closed = true
            @std_err_closed = true
          end

          ######################################################
          # Implements ReqContentHandler
          ######################################################

          def on_read_req_content(tur, buf, start, len, &callback)
            BayLog.debug("%s CGI:onReadReqContent: len=%d", tur, len)

            wrote_len = @std_in_rd.write(buf[start, len])
            BayLog.debug("%s CGI:onReadReqContent: wrote=%d", tur, wrote_len)
            tur.req.consumed(Tour::TOUR_ID_NOCHECK, len, &callback)
            access()
          end

          def on_end_req_content(tur)
            BayLog.trace("%s CGI:endReqContent", tur)
            access()
          end

          def on_abort_req(tur)
            BayLog.debug("%s CGI:abortReq", tur)
            agt = GrandAgent.get(tur.ship.agent_id)
            if !@std_out_closed
              @multiplexer.req_close(@std_out_rd)
            end
            if !@std_err_closed
              @multiplexer.req_close(@std_err_rd)
            end

            BayLog.debug("%s KILL PROCESS!: %d", tur, @pid)
            Process.kill('KILL', @pid)

            return false  # not aborted immediately
          end

          ######################################################
          # Other methods
          ######################################################

          def start_tour(env)
            @available = false

            std_in = IO.pipe()
            std_out = IO.pipe()
            std_err = IO.pipe()
            std_in[1].set_encoding("ASCII-8BIT")
            std_out[0].set_encoding("ASCII-8BIT")
            std_err[0].set_encoding("ASCII-8BIT")

            command = @cgi_docker.create_command(env)
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

            @std_out_closed = false
            @std_err_closed = false
            access()
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

          def process_finished()
            BayLog.debug("%s CGI Process finished: pid=%s", @tour, @pid)

            pid, stat = Process.wait2(@pid)
            print(stat)

            BayLog.debug("%s CGI Process finished: pid=%s code=%s", @tour, pid, stat.exitstatus)

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
          end
        end
      end
    end
  end
end
