require 'baykit/bayserver/tours/req_content_handler'
require 'baykit/bayserver/tours/tour'

module Baykit
  module BayServer
    module Docker
      module SendFile
        class FileContentHandler
          include Baykit::BayServer::Tours::ReqContentHandler   # implements
          include Baykit::BayServer::Tours

          attr :path
          attr :abortable

          def initialize(path)
            @path = path
            @abortable = true
          end

          ######################################################
          # Implements ReqContentHandler
          ######################################################

          def on_read_content(tur, buf, start, len)
            BayLog.debug("%s onReadReqContent(Ignore) len=%d", tur, len)
          end

          def on_end_content(tur)
            BayLog.debug("%s endReqContent", tur)
            tur.res.send_file(Tour::TOUR_ID_NOCHECK, path, tur.res.charset, true)
            @abortable = false
          end

          def on_abort(tur)
            BayLog.debug("%s onAbortReq aborted=%s", tur, abortable)
            return abortable
          end

        end
      end
    end
  end
end
