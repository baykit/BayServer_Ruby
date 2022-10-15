require 'baykit/bayserver/http_exception'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/agent/transporter/plain_transporter'
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
        attr :consume_listener

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
          @consume_listener = nil

          @can_compress = false
          @compressor = nil
          @headers.clear()
          @bytes_posted = 0
          @bytes_consumed = 0
          @bytes_limit = 0
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

          @tour.ship.send_headers(@tour.ship_id, @tour)
          @header_sent = true
        end

        def send_redirect(chk_tour_id, status, location)
          @tour.check_tour_id(chk_tour_id)

          if @header_sent
            BayLog.error("Try to redirect after response header is sent (Ignore)")
          else
            set_consume_listener(&ContentConsumeListener::DEV_NULL)
            @tour.ship.send_redirect(@tour.ship_id, @tour, status, location)
            @header_sent = true
            end_content(chk_tour_id)
          end

        end

        def set_consume_listener(&listener)
          @consume_listener = listener
          @bytes_consumed = 0
          @bytes_posted = 0
          @available = true
        end

        def send_content(chk_tour_id, buf, ofs, len)
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


          if @consume_listener == nil
            raise Sink.new("Response consume listener is null")
          end

          BayLog.debug("%s posted res content len=%d posted=%d limit=%d consumed=%d",
          @tour, len, @bytes_posted, @bytes_limit, @bytes_consumed)
          if @bytes_limit > 0 && @bytes_limit < self.bytes_posted
            raise ProtocolException.new("Post data exceed content-length: " + @bytes_posted + "/" + @bytes_limit)
          end

          if @can_compress
            get_compressor().compress(buf, ofs, len, &done_lis)
          else
            begin
              @tour.ship.send_res_content(@tour.ship_id, @tour, buf, ofs, len, &done_lis)
            rescue IOError => e
              done_lis.call()
              raise e
            end
          end

          @bytes_posted += len

          BayLog.debug("%s post res content: len=%d posted=%d limit=%d consumed=%d",
                       @tour, len, @bytes_posted, @bytes_limit, @bytes_consumed)

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

        def end_content(chk_tour_id)
          @tour.check_tour_id(chk_tour_id)

          BayLog.debug("%s end ResContent", self)

          if !@tour.zombie? && @tour.city != nil
            @tour.city.log(@tour)
          end

          # send end message
          if @can_compress
            get_compressor().finish()
          end


          # Done listener
          done_lis = Proc.new() do
            @tour.ship.return_tour(@tour)
          end

          begin
            @tour.ship.send_end_tour(@tour.ship_id, chk_tour_id, @tour, &done_lis)
          rescue IOError => e
            done_lis.call()
            raise e
          end
        end

        def consumed(check_id, length)
          @tour.check_tour_id(check_id)
          if @consume_listener == nil
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

          if !@tour.zombie?
            @consume_listener.call(length, resume)
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
            BayLog.error("Try to send error after response header is sent (Ignore)")
            BayLog.error("%s: status=%d, message=%s", self, status, msg)
            if err != nil
              BayLog.error_e(err);
            end
          else
            set_consume_listener(&ContentConsumeListener::DEV_NULL)
            @tour.ship.send_error(@tour.ship_id, @tour, status, msg, err)
            @header_sent = true
          end

          end_content(chk_tour_id)
        end



        def send_file(chk_tour_id, file, charset, async)
          @tour.check_tour_id(chk_tour_id)

          if @tour.zombie?
            return
          end

          if File.directory?(file)
            raise HttpException.new HttpStatus::FORBIDDEN, file
          elsif !File.exists?(file)
            raise HttpException.new HttpStatus::NOT_FOUND, file
          end

          mime_type = nil

          rname = File.basename(file)
          pos = rname.rindex('.')
          if pos
            ext = rname[pos + 1 .. -1].downcase
            mime_type = Mimes.type(ext)
          end

          if !mime_type
            mime_type = "application/octet-stream"
          end

          if mime_type.start_with?("text/") && charset != nil
            mime_type = mime_type + "; charset=" + charset
          end

          file_len = ::File.size(file)
          BayLog.debug("%s send_file %s async=%s len=%d", @tour, file, async, file_len)

          @headers.set_content_type(mime_type)
          @headers.set_content_length(file_len)

          begin
            send_headers(Tour::TOUR_ID_NOCHECK)

            if async
              bufsize = @tour.ship.protocol_handler.max_res_packet_data_size()

              case(BayServer.harbor.file_send_method())

              when Harbor::FILE_SEND_METHOD_SELECT
                tp = PlainTransporter.new(false, bufsize)
                @yacht.init(@tour, file, tp)
                tp.init(@tour.ship.agent.non_blocking_handler, File.open(file, "rb"), @yacht)
                @tour.ship.resume(@tour.ship_id)
                tp.open_valve()

              when Harbor::FILE_SEND_METHOD_SPIN
                timeout = 10
                tp = SpinReadTransporter.new(bufsize)
                @yacht.init(@tour, file, tp)
                tp.init(@tour.ship.agent.spin_handler, @yacht, File.open(file, "rb"), File.size(file), timeout, nil)
                @tour.ship.resume(@tour.ship_id)
                tp.open_valve()

              when Harbor::FILE_SEND_METHOD_TAXI
                txi = ReadFileTaxi.new(bufsize)
                @yacht.init(@tour, file, txi)
                txi.init(File.open(file, "rb"), @yacht)
                if !TaxiRunner.post(txi)
                  raise HttpException.new(HttpStatus.SERVICE_UNAVAILABLE, "Taxi is busy!");
                end

              else
                raise Sink.new();
              end

            else
              SendFileTrain.new(@tour, file).run()
            end
          rescue HttpException => e
            raise e
          rescue => e
            raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR, file)
          end

        end

        def get_compressor()
          if @compressor == nil
            @compressor = GzipCompressor.new(lambda do |new_buf, new_ofs, new_len, &lis|
              @tour.ship.send_res_content(@tour.ship_id, @tour, new_buf, new_ofs, new_len, &lis)
            end)
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
