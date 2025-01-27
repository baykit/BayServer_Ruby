module Baykit
  module BayServer
    module Tours

      module ReqContentHandler # interface
        def on_read_req_content(tur, buf, start, len)
          raise NotImplementedError.new
        end

        def on_end_req_content(tur)
          raise NotImplementedError.new
        end

        def on_abort_req(tur)
          raise NotImplementedError.new
        end

        #DEV_NULL = nil

        class DevNullReqContentHandler
          include ReqContentHandler  # implements
          def on_read_req_content(tur, buf, start, len)
          end

          def on_end_req_content(tur)
          end

          def on_abort_req(tur)
            return false
          end

        end
      end
    end
  end
end

Baykit::BayServer::Tours::ReqContentHandler::DEV_NULL = Baykit::BayServer::Tours::ReqContentHandler::DevNullReqContentHandler.new


