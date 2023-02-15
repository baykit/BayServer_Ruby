require 'baykit/bayserver/train/train'
require 'baykit/bayserver/tours/req_content_handler'

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
          include Baykit::BayServer::Util

          READ_CHUNK_SIZE = 8192

          attr :cgi_docker
          attr :tour
          attr :tour_id
          attr :available
          attr :pid
          attr :std_in
          attr :std_out
          attr :std_err
          attr :std_out_closed
          attr :std_err_closed

          def initialize(cgi_docker, tur)
            @cgi_docker = cgi_docker
            @tour = tur
            @tour_id = tur.tour_id
          end

          ######################################################
          # Implements ReqContentHandler
          ######################################################

          def on_read_content(tur, buf, start, len)
            BayLog.debug("%s CGI:onReadReqContent: len=%d", tur, len)

            wrote_len = @std_in[1].write(buf[start, len])
            BayLog.debug("%s CGI:onReadReqContent: wrote=%d", tur, wrote_len)
            tur.req.consumed(Tour::TOUR_ID_NOCHECK, len)
          end

          def on_end_content(tur)
            BayLog.trace("%s CGI:endReqContent", tur)
          end

          def on_abort(tur)
            BayLog.debug("%s CGI:abortReq", tur)
            if !@std_out_closed
              @tour.ship.agent.non_blocking_handler.ask_to_close(@std_out[0])
            end
            if !@std_err_closed
              @tour.ship.agent.non_blocking_handler.ask_to_close(@std_err[0])
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

            @std_in = IO.pipe()
            @std_out = IO.pipe()
            @std_err = IO.pipe()
            @std_in[1].set_encoding("ASCII-8BIT")
            @std_out[0].set_encoding("ASCII-8BIT")
            @std_err[0].set_encoding("ASCII-8BIT")

            command = @cgi_docker.create_command(env)
            BayLog.debug("%s Spawn: %s", @tour, command)
            @pid = Process.spawn(env, command, :in => @std_in[0], :out => @std_out[1], :err => @std_err[1])
            BayLog.debug("%s created process; %s", @tour, @pid)

            @std_in[0].close()
            @std_out[1].close()
            @std_err[1].close()
            BayLog.debug("#{@tour} PID: #{pid}")

            @std_out_closed = false
            @std_err_closed = false

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

          def process_finished()
            pid, stat = Process.wait2(@pid)

            BayLog.debug("%s CGI Process finished: pid=%s code=%s", @tour, pid, stat.exitstatus)
            if pid == nil
              BayLog.error("Process not finished: %d", @pid)
            end

            begin
              if stat.exitstatus != 0
                # Exec failed
                BayLog.error("%s CGI Invalid exit status pid=%d code=%s", @tour, @pid, stat.exitstatus)
                @tour.res.send_error(@tour_id, HttpStatus::INTERNAL_SERVER_ERROR, "Invalid exit Status")
              else
                @tour.res.end_content(@tour_id)
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
