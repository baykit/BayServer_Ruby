require 'baykit/bayserver/http_exception'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/util/headers'

module Baykit
  module BayServer
    module Tours
      class TourReq
        include Baykit::BayServer::Util::Reusable # implements

        include Baykit::BayServer
        include Baykit::BayServer::Protocol
        include Baykit::BayServer::Util

        ###########################
        #  Request Header info
        ###########################
        attr :tour   # parent object
        attr :key    # request id in FCGI or stream id in HTTP/2

        attr_accessor :uri
        attr_accessor :protocol
        attr_accessor :method

        attr :headers

        attr_accessor :rewritten_uri # set if URI is rewritten
        attr_accessor :query_string
        attr_accessor :path_info
        attr_accessor :script_name
        attr_accessor :req_host  # from Host header
        attr_accessor :req_port  # from Host header

        attr_accessor :remote_user
        attr_accessor :remote_pass

        attr_accessor :remote_address
        attr_accessor :remote_port
        attr_accessor :remote_host_func   # function
        attr_accessor :server_address
        attr_accessor :server_port
        attr_accessor :server_name
        attr_accessor :charset

        attr :content_handler

        ###########################
        # Request content info
        ###########################
        # Handling request contents
        attr :bytes_posted
        attr :bytes_consumed
        attr :bytes_limit

        attr :available
        attr :ended

        def initialize(tur)
          @headers = Headers.new()
          @tour = tur
        end

        def init(key)
          @key = key
        end

        ######################################################
        # Implements Reusable
        ######################################################
        def reset()
          @headers.clear

          @uri = nil
          @method = nil
          @protocol = nil
          @bytes_posted = 0
          @bytes_consumed = 0
          @bytes_limit = 0

          @key = 0

          @rewritten_uri = nil
          @query_string = nil
          @path_info = nil
          @script_name = nil
          @req_host = nil
          @req_port = 0
          @remote_user = nil
          @remote_pass = nil

          @remote_address = nil
          @remote_port = 0
          @remote_host_func = nil
          @server_address = nil
          @server_port = 0
          @server_name = nil

          @charset = nil
          @available = false
          @content_handler = nil
          @ended = false

        end

        ######################################################
        # other methods
        ######################################################

        def remote_host
          return @remote_host_func.call()
        end

        def set_limit(limit)
          if limit < 0
            raise Sink.new("invalid limit")
          end
          @bytes_limit = limit
          @bytes_posted = 0
          @bytes_consumed = 0
          @available = true
        end

        def post_req_content(check_id, data, start, len, &callback)
          @tour.check_tour_id(check_id)

          data_passed = false
          if  @tour.error != nil
            # If has error, only read content. (Do not call content handler)
            BayLog.debug("%s tour has error.", @tour)

          elsif !@tour.reading?
            raise HttpException.new(HttpStatus.BAD_REQUEST, "%s tour is not reading.", @tour)

          elsif @content_handler == nil
            BayLog.warn("%s content read, but no content handler", tour)

          elsif @bytes_posted + len > @bytes_limit
            raise ProtocolException.new("Read data exceed content-length: %d/%d", @bytes_posted + len, @bytes_limit)

          else
            @content_handler.on_read_req_content(@tour, data, start, len, &callback)
            data_passed = true
          end

          @bytes_posted += len
          BayLog.debug("%s post req content: len=%d posted=%d limit=%d consumed=%d",
                       @tour, len, @bytes_posted, @bytes_limit, @bytes_consumed)

          if !data_passed
            return true
          end

          old_available = @available
          if !buffer_available()
            @available = false
          end

          if old_available && !@available
            BayLog.debug("%s request unavailable (_ _): posted=%d consumed=%d", self,  @bytes_posted, @bytes_consumed);
          end

          return @available
        end

        def end_req_content(check_id)
          @tour.check_tour_id(check_id)
          if @ended
            raise Sink.new("#{@tour} Request content is already ended")
          end
          @tour.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::RUNNING)

          if @bytes_limit >= 0 && @bytes_posted != @bytes_limit
            raise ProtocolException.new("Read data exceed content-length: #{@bytes_posted}/#{@bytes_limit}")
          end

          if @content_handler != nil
            @content_handler.on_end_req_content(@tour)
          end
          @ended = true
        end

        def consumed(chk_id, length, &callback)
          @tour.check_tour_id(chk_id)

          @bytes_consumed += length
          BayLog.debug("%s reqConsumed: len=%d posted=%d limit=%d consumed=%d",
                       @tour, length, @bytes_posted, @bytes_limit, @bytes_consumed)

          resume = false
          old_available = @available
          if buffer_available()
            @available = true
          end

          if !old_available && @available
            BayLog.debug("%s request available (^o^): posted=%d consumed=%d", self,  @bytes_posted, @bytes_consumed);
            resume = true
          end
          callback.call(length, resume)
        end

        def abort
          BayLog.debug("%s abort", @tour)
          if @tour.preparing?
            #@tour.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ABORTED)
            return true

          elsif @tour.reading?
            aborted = true
            if @content_handler != nil
              aborted = @content_handler.on_abort_req(@tour)
            end

            return aborted
          else
            BayLog.debug("%s tour is not preparing or not running", @tour)
            return false
          end

        end

        def set_content_handler(hnd)
          if hnd == nil
            raise Sink.new("nil")
          end
          if @content_handler != nil
            raise Sink.new("content handler already set")
          end

          @content_handler = hnd
        end

        def buffer_available()
          return @bytes_posted - @bytes_consumed < BayServer.harbor.tour_buffer_size
        end
      end
    end
  end
end
