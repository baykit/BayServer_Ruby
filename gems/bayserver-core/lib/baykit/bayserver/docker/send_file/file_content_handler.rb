require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/http_exception'
require 'baykit/bayserver/tours/req_content_handler'
require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/util/directory_exception'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/docker/send_file/directory_train'

module Baykit
  module BayServer
    module Docker
      module SendFile
        class FileContentHandler
          include Baykit::BayServer::Tours::ReqContentHandler   # implements
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Util

          attr :tour
          attr :path
          attr :charset
          attr :list_files
          attr :abortable

          def initialize(tur, path, charset, list_files)
            @tour = tur
            @path = path
            @charset = charset
            @abortable = true
            @list_files = list_files
            @lock = Mutex.new
          end

          ######################################################
          # Implements ReqContentHandler
          ######################################################

          def on_read_req_content(tur, buf, start, len, &lis)
            BayLog.debug("%s file:on_read_req_content(Ignore) len=%d", tur, len)
            tur.req.consumed(tur.tour_id, len, &lis)
          end

          def on_end_req_content(tur)
            BayLog.debug("%s file:end_req_content", tur)
            req_start_tour
            @abortable = false
          end

          def on_abort_req(tur)
            BayLog.debug("%s file:on_abort aborted=%s", tur, @abortable)
            return @abortable
          end

          ######################################################
          # Sending file methods
          ######################################################

          def req_start_tour
            @lock.synchronize do
              BayLog.debug("%s req_start_tour", @tour)

              begin
                @tour.res.send_file(@path, @charset)
              rescue DirectoryException => e
                handle_directory(@tour, @path)
              rescue Errno::ENOENT => e
                raise HttpException.new(HttpStatus::NOT_FOUND, @path)
              rescue HttpException
                raise
              rescue => e
                BayLog.error_e(e)
                raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR, @path)
              end
            end
          end

          private

          def handle_directory(tur, path)
            if @list_files
              train = DirectoryTrain.new(tur, path)
              train.start_tour
            else
              raise HttpException.new(HttpStatus::FORBIDDEN, "Directory scan is prohibited")
            end
          end

        end
      end
    end
  end
end
