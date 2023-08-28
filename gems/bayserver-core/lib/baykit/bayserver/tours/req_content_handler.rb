module Baykit
  module BayServer
    module Tours

      module ReqContentHandler
        #
        # interface
        #
        #         void onReadContent(Tour tur, byte[] buf, int start, int len) throws IOException;
        #         void onEndContent(Tour tur) throws IOException, HttpException;
        #         void onAbort(Tour tur);
        #

        #DEV_NULL = nil
      end

      class DevNullReqContentHandler
        include ReqContentHandler  # implements
        def on_read_content(tur, buf, start, len)
        end

        def on_end_content(tur)
        end

        def on_abort(tur)
          return false
        end
      end

      module ReqContentHandler
        DEV_NULL = DevNullReqContentHandler.new()
      end
    end
  end
end


