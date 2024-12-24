require 'baykit/bayserver/http_exception'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/taxi/taxi_runner'
require 'baykit/bayserver/docker/harbor'
require 'baykit/bayserver/tours/send_file_yacht'
require 'baykit/bayserver/tours/read_file_taxi'
require 'baykit/bayserver/tours/content_consume_listener'

require 'baykit/bayserver/util/counter'
require 'baykit/bayserver/util/headers'
require 'baykit/bayserver/util/byte_array'
require 'baykit/bayserver/util/gzip_compressor'

module Baykit
  module BayServer
    module Tours
      class TourRes
        include Baykit::BayServer::Util::Reusable # implements

        include Baykit::BayServer::Util
        include Baykit::BayServer::Docker
        include Baykit::BayServer::Tours
        include Baykit::BayServer::Taxi
        include Baykit::BayServer::Agent::Transporter

        attr :tour

        ###########################
        #  Response Header info
        ###########################
        attr :headers
        attr_accessor :charset
        attr :available
        attr :res_consume_listener

        attr_accessor :header_sent
        attr :yacht

        ###########################
        #  Response Content info
        ###########################
        attr :can_compress
        attr :compressor

        attr :bytes_posted
        attr :bytes_consumed
        attr :bytes_limit
        attr :buffer_size

        def initialize(tur)
          @headers = Headers.new()
          @tour = tur
          @buffer_size = BayServer.harbor.tour_buffer_size
        end

        def init()
          @yacht = SendFileYacht.new()
        end

        def to_s()
          return @tour.to_s()
        end

        ######################################################
        # Implements Reusable
        ######################################################

        def reset()
          @charset = nil
          @header_sent = false
          if @yacht != nil
            @yacht.reset()
          end

          @available = false
          @res_consume_listener = nil

          @can_compress = false
          @compressor = nil
          @headers.clear()
          @bytes_posted = 0
          @bytes_consumed = 0
          @bytes_limit = 0
          @tour_returned = false
        end

        ######################################################
        # other methods
        ######################################################

        def send_headers(chk_tour_id)
          @tour.check_tour_id(chk_tour_id)

          if @tour.zombie?
            return
          end

          if @header_sent
            return
          end

          @bytes_limit = @headers.content_length()
          BayLog.debug("%s send_headers content length: %s", self, @bytes_limit)

          # Compress check
          if BayServer.harbor.gzip_comp &&
            @headers.contains(Headers::CONTENT_TYPE) &&
            @headers.content_type().downcase().start_with?("text/") &&
            !@headers.contains(Headers::CONTENT_ENCODING)

            enc = @tour.req.headers.get(Headers::ACCEPT_ENCODING)

            if enc != nil
              enc.split(",").each do |tkn|
                if tkn.strip().casecmp?("gzip")
                  @can_compress = true
                  @headers.set(Headers::CONTENT_ENCODING, "gzip")
                  @headers.remove(Headers::CONTENT_LENGTH)
                  break
                end
              end
            end
          end

          begin
            handled = false
            if !@tour.error_handling && @tour.res.headers.status >= 400
              trouble = BayServer.harbor.trouble
              if trouble != nil
                cmd = trouble.find(tur.res.headers.status)
                if cmd != nil
                  err_tour = get_error_tour
                  err_tour.req.uri = cmd.target
                  @tour.req.headers.copy_to(err_tour.req.headers)
                  @tour.res.headers.copy_to(err_tour.res.headers)
                  err_tour.req.remote_port = @tour.req.remote_port
                  err_tour.req.remote_address = @tour.req.remote_address
                  err_tour.req.server_address = @tour.req.server_address
                  err_tour.req.server_port = @tour.req.server_port
                  err_tour.req.server_name = @tour.req.server_name
                  err_tour.res.header_sent = @tour.res.header_sent
                  @tour.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ZOMBIE)
                  case cmd.method
                  when :GUIDE
                    err_tour.go
                  when :TEXT
                    @protocol_handler.send_headers(err_tour)
                    data = cmd.target
                    err_tour.res.send_res_content(Tour::TOUR_ID_NOCHECK, data, 0, data.length)
                    err_tour.end_res_content(Tour::TOUR_ID_NOCHECK)
                  when :REROUTE
                    err_tour.res.send_http_exception(Tour::TOUR_ID_NOCHECK, HttpException.moved_temp(cmd.target))
                  end
                  handled = true
                end
              end
            end

            if !handled
              @tour.ship.send_headers(@tour.ship_id, @tour)
            end
          rescue IOError => e
            BayLog.debug_e(e, "%s abort: %s", @tour, e)
            @tour.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ABORTED)
            raise e
          ensure
            @header_sent = true
          end

        end

        def send_redirect(chk_tour_id, status, location)
          @tour.check_tour_id(chk_tour_id)

          if @header_sent
            BayLog.error("Try to redirect after response header is sent (Ignore)")
          else
            set_consume_listener(&ContentConsumeListener::DEV_NULL)
            begin
              @tour.ship.send_redirect(@tour.ship_id, @tour, status, location)
            rescue IOError => e
              @tour.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ABORTED)
              raise e
            ensure
              @header_sent = true
              end_content(chk_tour_id)
            end
          end

        end

        def set_consume_listener(&listener)
          @res_consume_listener = listener
          @bytes_consumed = 0
          @bytes_posted = 0
          @available = true
        end

        def send_res_content(chk_tour_id, buf, ofs, len)
          @tour.check_tour_id(chk_tour_id)
          BayLog.debug("%s sendContent len=%d", @tour, len)

          # Done listener
          done_lis = Proc.new() do
            consumed(chk_tour_id, len);
          end

          if @tour.zombie?
            BayLog.debug("%s zombie return", self)
            done_lis.call()
            return true
          end

          if !@header_sent
            raise Sink.new("Header not sent")
          end


          if @res_consume_listener == nil
            raise Sink.new("Response consume listener is null")
          end

          @bytes_posted += len
          BayLog.debug("%s posted res content len=%d posted=%d limit=%d consumed=%d",
          @tour, len, @bytes_posted, @bytes_limit, @bytes_consumed)
          if @bytes_limit > 0 && @bytes_limit < self.bytes_posted
            raise ProtocolException.new("Post data exceed content-length: " + @bytes_posted + "/" + @bytes_limit)
          end

          if @tour.zombie? || @tour.aborted?
            # Don't send peer any data
            BayLog::debug("%s Aborted or zombie tour. do nothing: %s state=%s", self, @tour, @tour.state)
            done_lis.call()
          else
            if @can_compress
              get_compressor().compress(buf, ofs, len, &done_lis)
            else
              begin
                @tour.ship.send_res_content(@tour.ship_id, @tour, buf, ofs, len, &done_lis)
              rescue IOError => e
                done_lis.call()
                @tour.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ABORTED)
                raise e
              end
            end
          end


          old_available = @available
          if !buffer_available()
            @available = false
          end
          if old_available && !@available
            BayLog.debug("%s response unavailable (_ _): posted=%d consumed=%d (buffer=%d)",
                         self, @bytes_posted, @bytes_consumed, @buffer_size)
          end

          return @available
        end

        def end_res_content(chk_tour_id)
          @tour.check_tour_id(chk_tour_id)

          BayLog.debug("%s end ResContent", self)
          if @tour.ended?
            BayLog.debug("%s Tour is already ended (Ignore).", self)
            return
          end

          if !@tour.zombie? && @tour.city != nil
            @tour.city.log(@tour)
          end

          # send end message
          if @can_compress
            get_compressor().finish()
          end


          # Done listener
          tour_returned = false
          done_lis = Proc.new() do
            @tour.check_tour_id(chk_tour_id)
            @tour.ship.return_tour(@tour)
            tour_returned = true
          end

          begin
            if @tour.zombie? || @tour.aborted?
              # Don't send peer any data. Do nothing
              BayLog.debug("%s Aborted or zombie tour. do nothing: %s state=%s", self, @tour, @tour.state)
              done_lis.call()
            else
              begin
                @tour.ship.send_end_tour(@tour.ship_id, @tour, &done_lis)
              rescue IOError => e
                BayLog.debug("%s Error on sending end tour", self)
                done_lis.call()
                raise e
              end
            end
          ensure
            # If tour is returned, we cannot change its state because
            # it will become uninitialized.
            BayLog.debug("%s tur#%d is returned: %s", self, chk_tour_id, tour_returned)
            if !tour_returned
              @tour.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ENDED)
            end
          end
        end

        def consumed(check_id, length)
          @tour.check_tour_id(check_id)
          if @res_consume_listener == nil
            raise Sink.new("Response consume listener is null")
          end

          @bytes_consumed += length

          BayLog.debug("%s resConsumed: len=%d posted=%d consumed=%d limit=%d",
                       @tour, length, @bytes_posted, @bytes_consumed, @bytes_limit)

          resume = false
          old_available = @available
          if buffer_available()
            @available = true
          end
          if !old_available && @available
            BayLog.debug("%s response available (^o^): posted=%d consumed=%d", self,  @bytes_posted, @bytes_consumed)
            resume = true
          end

          if @tour.running?
            @res_consume_listener.call(length, resume)
          end
        end

        def send_http_exception(chk_tour_id, http_ex)
          if http_ex.status == HttpStatus::MOVED_TEMPORARILY || http_ex.status == HttpStatus::MOVED_PERMANENTLY
            send_redirect(chk_tour_id, http_ex.status, http_ex.location)
          else
            send_error(chk_tour_id, http_ex.status, http_ex.message, http_ex)
          end
        end

        def send_error(chk_tour_id, status=HttpStatus::INTERNAL_SERVER_ERROR, msg="", err=nil)
          @tour.check_tour_id(chk_tour_id)
          #BayLog.debug "#{self} Tur: Send Error status=#{status} msg=#{msg}"

          if @tour.zombie?
            return
          end


          if err.instance_of?(HttpException)
            status = err.status
            msg = err.message
          end

          if @header_sent
            BayLog.debug("Try to send error after response header is sent (Ignore)")
            BayLog.debug("%s: status=%d, message=%s", self, status, msg)
            if err != nil
              BayLog.error_e(err);
            end
          else
            set_consume_listener(&ContentConsumeListener::DEV_NULL)

            if @tour.zombie? || @tour.aborted?
              # Don't send peer any data. Do nothing
              BayLog.debug("%s Aborted or zombie tour. do nothing: %s state=%s", self, @tour, @tour.state)
            else
              begin
                @tour.ship.send_error(@tour.ship_id, @tour, status, msg, err)
              rescue IOError => e
                BayLog.debug_e(e, "%s Error on sending error", self)
                @tour.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ABORTED)
              end
              @header_sent = true
            end
          end

          end_res_content(chk_tour_id)
        end

        def get_compressor()
          if @compressor == nil
            sip_id = @tour.ship.ship_id
            tur_id = @tour.tour_id
            gz_callback = lambda do |new_buf, new_ofs, new_len, &lis|
              begin
                @tour.ship.send_res_content(sip_id, @tour, new_buf, new_ofs, new_len, &lis)
              rescue IOError => e
                @tour.change_state(tur_id, Tour::TourState::ABORTED)
                raise e
              end
            end

            @compressor = GzipCompressor.new(gz_callback)
          end

          return @compressor
        end


        def buffer_available()
          return @bytes_posted - @bytes_consumed < @buffer_size
        end
      end
    end
  end
end
