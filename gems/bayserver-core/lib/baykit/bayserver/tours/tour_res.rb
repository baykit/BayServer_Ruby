require 'baykit/bayserver/http_exception'
require 'baykit/bayserver/sink'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/common/rudder_state_store'
require 'baykit/bayserver/taxi/taxi_runner'
require 'baykit/bayserver/docker/harbor'
require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/tours/read_file_taxi'
require 'baykit/bayserver/tours/content_consume_listener'
require 'baykit/bayserver/tours/file_store'
require 'baykit/bayserver/tours/send_file_ship'

require 'baykit/bayserver/util/counter'
require 'baykit/bayserver/util/headers'
require 'baykit/bayserver/util/byte_array'
require 'baykit/bayserver/util/directory_exception'
require 'baykit/bayserver/util/gzip_compressor'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/util/mimes'

module Baykit
  module BayServer
    module Tours
      class TourRes
        include Baykit::BayServer::Util::Reusable # implements

        include Baykit::BayServer::Util
        include Baykit::BayServer::Docker
        include Baykit::BayServer::Tours
        include Baykit::BayServer::Taxi

        attr :tour

        ###########################
        #  Response Header info
        ###########################
        attr :headers
        attr_accessor :charset
        attr :res_consume_listener

        attr_accessor :header_sent

        ###########################
        #  Response Content info
        ###########################
        attr :can_compress
        attr :compressor

        attr :bytes_posted
        attr :bytes_limit

        # Whether to send via Direct Boarding (sendfile API)
        attr_accessor :direct_boarding

        def initialize(tur)
          @headers = Headers.new()
          @tour = tur
        end

        def init()
          @direct_boarding = BayServer.harbor.direct_boarding
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

          @res_consume_listener = nil

          @can_compress = false
          @compressor = nil
          @headers.clear()
          @bytes_posted = 0
          @bytes_limit = 0
          @tour_returned = false
          @direct_boarding = false
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

          if @tour.cargo != nil
            @tour.cargo.save_headers(@headers)
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
              end_res_content(chk_tour_id)
            end
          end

        end

        def set_consume_listener(&listener)
          @res_consume_listener = listener
          @bytes_posted = 0
        end

        def send_res_content(chk_tour_id, buf, ofs, len)
          @tour.check_tour_id(chk_tour_id)
          BayLog.debug("%s sendContent len=%d cargo=%s", @tour, len, @tour.cargo)

          if @tour.cargo != nil
            @tour.cargo.save_content(buf, ofs, len)
          end

          # Done listener: |avail| carries the post-write buffer state
          # so the resConsumeListener can decide whether to resume.
          done_lis = Proc.new() do |avail|
            consumed(chk_tour_id, len, avail)
          end

          if @tour.zombie?
            BayLog.debug("%s zombie return", self)
            done_lis.call(true)
            return true
          end

          if !@header_sent
            raise Sink.new("Header not sent")
          end


          if @res_consume_listener == nil
            raise Sink.new("Response consume listener is null")
          end

          @bytes_posted += len
          BayLog.debug("%s posted res content len=%d posted=%d limit=%d",
          @tour, len, @bytes_posted, @bytes_limit)
          if @bytes_limit > 0 && @bytes_limit < self.bytes_posted
            raise ProtocolException.new("Post data exceed content-length: " + @bytes_posted + "/" + @bytes_limit)
          end

          available = true
          if @tour.zombie? || @tour.aborted?
            # Don't send peer any data
            BayLog::debug("%s Aborted or zombie tour. do nothing: %s state=%s", self, @tour, @tour.state)
            done_lis.call(true)
          else
            if @can_compress
              get_compressor().compress(buf, ofs, len, &done_lis)
            else
              begin
                available = @tour.ship.send_res_content(@tour.ship_id, @tour, buf, ofs, len, &done_lis)
              rescue IOError => e
                done_lis.call(true)
                @tour.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ABORTED)
                raise e
              end
            end
          end

          return available
        end

        def send_file(path, charset)
          info = nil
          rd = nil
          file_size = -1

          if @tour.ship.port_docker.protocol == "h1" &&
             !@tour.ship.port_docker.secure &&
             @direct_boarding
            # Send via directBoarding if the protocol is HTTP/1.x and unencrypted.
            info = FileStore.get_file_info(path)
            rd = info.rudder
            file_size = info.file_length
            @direct_boarding = info.rudder != nil
          else
            @direct_boarding = false
          end

          if rd == nil
            if File.directory?(path)
              raise DirectoryException.new
            else
              case BayServer.harbor.file_multiplexer
              when Harbor::MULTIPLEXER_TYPE_SPIDER, Harbor::MULTIPLEXER_TYPE_SPIN,
                   Harbor::MULTIPLEXER_TYPE_JOB, Harbor::MULTIPLEXER_TYPE_TAXI
                f = File.open(path, "rb")
                rd = Baykit::BayServer::Rudders::IORudder.new(f)
              else
                raise Sink.new
              end
              file_size = File.size(path)
            end
          end

          mtype = nil
          pos = path.rindex('.')
          if pos != nil
            ext = path[pos + 1 .. -1].downcase
            mtype = Mimes.type(ext)
          end

          if mtype == nil
            mtype = "application/octet-stream"
          end

          if mtype.start_with?("text/") && charset != nil
            mtype = mtype + "; charset=" + charset
          end

          @headers.set_content_type(mtype)
          @headers.set_content_length(file_size)
          send_headers(Tour::TOUR_ID_NOCHECK)

          if @direct_boarding
            tur_id = @tour.tour_id
            set_consume_listener do |len, resume|
              begin
                end_res_content(tur_id)
              rescue IOError => e
                BayLog.debug_e(e)
              end
            end
            transfer_content(Tour::TOUR_ID_NOCHECK, rd, 0, info.file_length)
          else
            bufsize = @tour.ship.protocol_handler.max_res_packet_data_size
            agt = Baykit::BayServer::Agent::GrandAgent.get(@tour.ship.agent_id)

            case BayServer.harbor.file_multiplexer
            when Harbor::MULTIPLEXER_TYPE_SPIDER
              mpx = agt.spider_multiplexer
            when Harbor::MULTIPLEXER_TYPE_SPIN
              mpx = agt.spin_multiplexer
            when Harbor::MULTIPLEXER_TYPE_JOB
              mpx = agt.job_multiplexer
            when Harbor::MULTIPLEXER_TYPE_TAXI
              mpx = agt.taxi_multiplexer
            else
              raise Sink.new
            end

            send_file_ship = SendFileShip.new
            tp = Baykit::BayServer::Agent::Multiplexer::PlainTransporter.new(
              mpx,
              send_file_ship,
              true,
              bufsize,
              false)

            send_file_ship.init(rd, tp, @tour)
            sid = send_file_ship.ship_id
            set_consume_listener do |len, resume|
              if resume
                send_file_ship.resume_read(sid)
              end
            end

            st = Baykit::BayServer::Common::RudderStateStore.get_store(agt.agent_id).rent
            st.init(rd, tp)
            mpx.add_rudder_state(rd, st)
            mpx.req_read(rd)
          end
        end

        def transfer_content(check_id, file_rd, ofs, len)
          BayLog.debug("%s transfer content: ofs=%d len=%d", self, ofs, len)

          # Done listener
          lis = Proc.new() do
            @tour.check_tour_id(check_id)
            @res_consume_listener.call(len, false)
          end

          if @tour.zombie?
            BayLog.debug("%s zombie tour. return", self)
            lis.call
            return
          end

          if !@header_sent
            raise Sink.new("Header not sent")
          end

          @bytes_posted += len
          BayLog.debug("%s posted res content len=%d posted=%d limit=%d",
                       @tour, len, @bytes_posted, @bytes_limit)

          if @tour.aborted?
            # Don't send peer any data. Do nothing
            BayLog.debug("%s Aborted tour. do nothing: %s state=%s", self, @tour, @tour.state)
            @tour.change_state(check_id, Tour::TourState::ENDED)
            lis.call
          else
            begin
              @tour.ship.transfer_res_content(@tour.ship_id, @tour, file_rd, ofs, len, &lis)
            rescue IOError => e
              BayLog.debug("%s error on sending resContent: %s", self, e)
              lis.call
              @tour.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ABORTED)
              raise e
            end
          end
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

          if @tour.cargo != nil
            @tour.cargo.end_save
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

        def consumed(check_id, length, buffer_available)
          @tour.check_tour_id(check_id)
          if @res_consume_listener == nil
            raise Sink.new("Response consume listener is null")
          end

          BayLog.debug("%s resConsumed: len=%d available=%s", @tour, length, buffer_available)

          @res_consume_listener.call(length, buffer_available)
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
      end
    end
  end
end
