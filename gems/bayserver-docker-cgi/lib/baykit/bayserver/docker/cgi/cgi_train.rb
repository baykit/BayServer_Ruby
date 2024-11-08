require 'baykit/bayserver/train/train'
require 'baykit/bayserver/tours/req_content_handler'

require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/http_status'

module Baykit
  module BayServer
    module Docker
      module Cgi
        class CgiTrain < Baykit::BayServer::Train::Train
          include Baykit::BayServer::Tours::ReqContentHandler   # implements

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Train
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Util

          READ_CHUNK_SIZE = 8192

          attr :cgi_docker
          attr :env
          attr :available
          attr :lock
          attr :pid
          attr :std_in
          attr :std_out
          attr :std_err

          def initialize(cgi_docker, tur)
            super(tur)
            @cgi_docker = cgi_docker
          end

          def start_tour(env)
            @env = env
            @available = false
            @lock = Mutex.new()

            @std_in = IO.pipe()
            @std_out = IO.pipe()
            @std_err = IO.pipe()
            @std_in[1].set_encoding("ASCII-8BIT")
            @std_out[0].set_encoding("ASCII-8BIT")
            @std_err[0].set_encoding("ASCII-8BIT")

            command = @cgi_docker.create_command(@env)
            BayLog.debug("%s Spawn: %s", @tour, command)
            @pid = Process.spawn(@env, command, :in => @std_in[0], :out => @std_out[1], :err => @std_err[1])
            @std_in[0].close()
            @std_out[1].close()
            @std_err[1].close()
            BayLog.debug("#{@tour} PID: #{pid}")

            @tour.req.set_content_handler(self)

          end

          def depart

            begin

              ###############
              # Handle StdOut
              HttpUtil.parse_message_headers(@std_out[0], @tour.res.headers)

              if BayServer.harbor.trace_header
                @tour.res.headers.names.each do |name|
                  @tour.res.headers.values(name).each do |value|
                    BayLog.info("%s CGI: resHeader: %s=%s", @tour, name, value)
                  end
                end
              end

              status = @tour.res.headers.get("Status")
              #BayLog.debug "Headers: #{@tours.res.headers.headers}"
              #BayLog.debug "Status: #{status}"
              if !StringUtil.empty?(status)
                pos = status.index(" ")
                if pos
                  code = status[0, pos].to_i
                else
                  code = status.to_i
                end
                @tour.res.headers.status = code
              end

              @tour.res.set_consume_listener do |len, resume|
                if resume
                  @available = true
                end
              end

              @tour.res.send_headers(@tour_id)

              #BayLog.info("Reading STDOUT")
              while true
                buf = StringUtil.alloc(READ_CHUNK_SIZE)
                c = std_out[0].read(READ_CHUNK_SIZE, buf)
                if !c
                  break
                end

                BayLog.trace("%s CGITrain: read stdout bytes: len=%d", @tour, buf.length)
                @available = @tour.res.send_content(@tour_id, buf, 0, buf.length)
                while !@available
                  sleep(0.1)
                end
              end

              #BayLog.info("Reading STDERR")
              ###############
              # Handle StdErr
              ###############
              while true
                buf = StringUtil.alloc(READ_CHUNK_SIZE)
                c = std_err[0].read(READ_CHUNK_SIZE, buf)
                if !c
                  break
                end

                BayLog.warn("%s CGITrain: read stderr bytes: %d", @tour, buf.length)
                BayLog.warn(buf)
              end

              @tour.res.end_content @tour_id

            rescue HttpException => e
              raise e
            rescue => e
              BayLog.error("%s CGITrain: Catch error: %s", @tour, e)
              BayLog.error_e(e)
              raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR, "CGI error")
            ensure
              begin
                BayLog.debug("%s CGITrain: waiting process end", @tour)
                Process.wait(@pid)
                close_pipes()

                BayLog.debug("%s CGITrain: process ended", @tour)
              rescue => e
                BayLog.error_e(e)
              end
            end
          end

          def on_read_content(tur, buf, start, len)
            BayLog.info("%s CGITrain:onReadContent: len=%d", tur, len)

            wrote_len = @std_in[1].write(buf[start, len])
            BayLog.info("%s CGITrain:onReadContent: wrote=%d", tur, wrote_len)
            tur.req.consumed(Tour::TOUR_ID_NOCHECK, len)
          end

          def on_end_content(tur)
            BayLog.trace("%s CGITrain:endContent", tur)

            if !TrainRunner.post(self)
              raise HttpException.new(HttpStatus::SERVICE_UNAVAILABLE, "TrainRunner is busy")
            end
          end

          def on_abort(tur)
            BayLog.debug("%s CGITrain:abort", tur)
            close_pipes()

            BayLog.debug("%s KILL PROCESS!: %d", tur, @pid)
            Process.kill('KILL', @pid)

            return false  # not aborted immediately
          end

          def close_pipes()
            @std_in[1].close()
            @std_out[0].close()
            @std_err[0].close()
          end
        end
      end
    end
  end
end
