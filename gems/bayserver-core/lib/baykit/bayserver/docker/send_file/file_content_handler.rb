require 'baykit/bayserver/tours/req_content_handler'
require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/util/mimes'
require 'baykit/bayserver/docker/send_file/send_file_ship'
require 'baykit/bayserver/docker/send_file/wait_file_ship'

module Baykit
  module BayServer
    module Docker
      module SendFile
        class FileContentHandler
          include Baykit::BayServer::Tours::ReqContentHandler   # implements
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Agent::Multiplexer
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Util
          include Baykit::BayServer::Common

          attr :tour
          attr :path
          attr :charset
          attr :mime_type
          attr :abortable
          attr :store
          attr :file_content

          def initialize(tur, store, path, charset)
            @tour = tur
            @store = store
            @path = path
            @charset = charset
            @abortable = true

            rname = File.basename(path)
            pos = rname.rindex('.')
            if pos
              ext = rname[pos + 1 .. -1].downcase
              @mime_type = Mimes.type(ext)
            end

            if @mime_type == nil
              @mime_type = "application/octet-stream"
            end

            if @mime_type.start_with?("text/") && charset != nil
              @mime_type = @mime_type + "; charset=" + charset
            end
          end

          ######################################################
          # Implements ReqContentHandler
          ######################################################

          def on_read_req_content(tur, buf, start, len, &lis)
            BayLog.debug("%s onReadReqContent(Ignore) len=%d", tur, len)
            tur.req.consumed(tur.tour_id, len, &lis)
          end

          def on_end_req_content(tur)
            BayLog.debug("%s endReqContent", tur)
            req_start_tour()
            @abortable = false
          end

          def on_abort_req(tur)
            BayLog.debug("%s onAbortReq aborted=%s", tur, abortable)
            return abortable
          end

          ######################################################
          # Sending file methods
          ######################################################

          def req_start_tour

            if @store == nil
              status = FileStore::FileContentStatus.new(nil, FileStore::FileContentStatus::EXCEEDED)
            else
              status = @store.get(path)
            end
            @file_content = status.file_content

            BayLog.debug("%s file content status: %d", @tour, status.status)
            case status.status
            when FileStore::FileContentStatus::STARTED, FileStore::FileContentStatus::EXCEEDED
              send_file_async

            when FileStore::FileContentStatus::READING
              # Wait file loaded
              BayLog.debug("%s Cannot start tour (file reading)", @tour)

              agt = GrandAgent.get(@tour.ship.agent_id)
              wait_file_ship = WaitFileShip.new()
              tp = PlainTransporter.new(
                agt.spider_multiplexer,
                wait_file_ship,
                true,
                8192,
                false)

              begin
                pipe = IO::pipe
                source_rd = IORudder.new(pipe[0])
                source_rd.set_non_blocking()
                wait_rd = IORudder.new(pipe[1])
              rescue IOError => e
                raise Sink.new("Fatal error: %s", e)
              end

              wait_file_ship.init(source_rd, tp, @tour, @file_content, self)
              @tour.res.set_consume_listener(&ContentConsumeListener::DEV_NULL)

              st = RudderStateStore.get_store(agt.agent_id).rent()
              st.init(source_rd, tp)
              agt.spider_multiplexer.add_rudder_state(source_rd, st)
              agt.spider_multiplexer.req_read(source_rd)

              @file_content.add_waiter(wait_rd)

              when FileStore::FileContentStatus::COMPLETED
                send_file_from_cache

            else
              raise Sink.new("Unknown file content status: %d", status.status)
            end

          end

          def send_file_async()

            if File.directory?(@path)
              raise HttpException.new(HttpStatus::FORBIDDEN, @path)
            elsif !File.exist?(@path)
              raise HttpException.new(HttpStatus::NOT_FOUND, @path)
            end

            file_len = ::File.size(@path)

            @tour.res.headers.set_content_type(@mime_type)
            @tour.res.headers.set_content_length(File.size(@path))

            begin
              @tour.res.send_headers(Tour::TOUR_ID_NOCHECK)

              bufsize = @tour.ship.protocol_handler.max_res_packet_data_size
              agt = GrandAgent.get(@tour.ship.agent_id)

              f = File.open(@path, "rb")
              rd = IORudder.new(f)

              case(BayServer.harbor.file_multiplexer)

              when Harbor::MULTIPLEXER_TYPE_SPIDER
                mpx = agt.spider_multiplexer

              when Harbor::MULTIPLEXER_TYPE_JOB
                mpx = agt.job_multiplexer

              when Harbor::MULTIPLEXER_TYPE_SPIN
                mpx = agt.spin_multiplexer

              when Harbor::MULTIPLEXER_TYPE_TAXI
                mpx = agt.taxi_multiplexer

              else
                raise Sink.new
              end

              send_file_ship = SendFileShip.new
              tp = PlainTransporter.new(
                mpx,
                send_file_ship,
                true,
                8195,
                false)

              send_file_ship.init(rd, tp, @tour, @file_content)
              sid = send_file_ship.ship_id

              @tour.res.set_consume_listener do |len, resume|
                if resume
                  send_file_ship.resume_read(sid)
                end
              end

              st = RudderStateStore.get_store(agt.agent_id).rent()
              st.init(rd, tp)
              mpx.add_rudder_state(rd, st)
              mpx.req_read(rd)

            rescue IOError => e
              BayLog.error_e(e)
              raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR, file)
            end

          end

          def send_file_from_cache
            @tour.res.set_consume_listener(&ContentConsumeListener::DEV_NULL)
            @tour.res.headers.set_content_type(@mime_type)
            @tour.res.headers.set_content_length(File.size(@path))
            begin
              @tour.res.send_headers(Tour::TOUR_ID_NOCHECK)
              @tour.res.send_res_content(Tour::TOUR_ID_NOCHECK, @file_content.content, 0, @file_content.content_length)
              @tour.res.end_res_content(Tour::TOUR_ID_NOCHECK)
            rescue IOError => e
              BayLog.error_e(e)
              raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR, @file_content.path)
            end
          end

        end
      end
    end
  end
end
