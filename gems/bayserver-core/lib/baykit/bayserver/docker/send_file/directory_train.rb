require 'baykit/bayserver/http_exception'

require 'baykit/bayserver/train/train'
require 'baykit/bayserver/tours/req_content_handler'

require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/http_status'

module Baykit
  module BayServer
    module Docker
      module SendFile
        class DirectoryTrain < Baykit::BayServer::Train::Train
          include Baykit::BayServer::Tours::ReqContentHandler   # implements

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Train
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Util

          attr :path
          attr :available
          attr :abortable

          def initialize(tur, path)
            super(tur)
            @path = path
            @available = false
            @abortable = true
          end

          def start_tour()
            @tour.req.set_content_handler(self)
          end

          #######################################################
          # Implements Train
          #######################################################

          def depart()
            begin
              @tour.res.headers.set_content_type("text/html")

              @tour.res.set_consume_listener do |len, resume|
                if resume
                  @available = true
                end
              end

              @tour.res.send_headers(@tour_id)

              w = StringIO.new()
              w.write("<html><body><br>")

              if tour.req.uri != "/"
                print_link(w, "../")
              end

              Dir.foreach(path) do |f|
                if File.directory?(f)
                  if f != "." && f != ".."
                    print_link(w, "#{f}/")
                  end
                else
                  print_link(w, f)
                end
              end

              w.write("</body></html>")
              bytes = StringUtil.to_bytes(w.string())
              w.close()

              BayLog.trace("%s Directory: send contents: len=%d", @tour, bytes.length)
              @available = tour.res.send_content(@tour_id, bytes, 0, bytes.length)

              while !@available
                sleep(0.1)
              end

              tour.res.end_content(@tour_id)

            rescue IOError => e
              BayLog.error_e(e)
              raise HttpException.new(HttpStatus.INTERNAL_SERVER_ERROR, e)
            end
          end

          #######################################################
          # Implements ReqContentHandler
          #######################################################

          def on_read_content(tur, buf, start, len)
            BayLog.debug("%s onReadContent(Ignore) len=%d", tur, len)
          end

          def on_end_content(tur)
            BayLog.debug("%s endContent", tur)
            @abortable = false

            if !TrainRunner.post(self)
              raise HttpException.new(HttpStatus.SERVICE_UNAVAILABLE, "TourRunner is busy")
            end
          end

          def on_abort(tur)
            BayLog.debug("%s onAbort aborted=%s", tur, @abortable)
            return @abortable
          end


          def print_link(w, path)
            w.write("<a href='#{path}'>")
            w.write(path)
            w.write("</a><br>")
          end

        end
      end
    end
  end
end


