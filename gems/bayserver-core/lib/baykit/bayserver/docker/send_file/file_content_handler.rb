require 'baykit/bayserver/tours/req_content_handler'
require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/util/mimes'
require 'baykit/bayserver/docker/send_file/send_file_ship'

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

          attr :path
          attr :abortable

          def initialize(path)
            @path = path
            @abortable = true
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
            send_file_async(tur, path, tur.res.charset)
            @abortable = false
          end

          def on_abort_req(tur)
            BayLog.debug("%s onAbortReq aborted=%s", tur, abortable)
            return abortable
          end

          ######################################################
          # Sending file methods
          ######################################################

          def send_file_async(tur, file, charset)

            if File.directory?(file)
              raise HttpException.new HttpStatus::FORBIDDEN, file
            elsif !File.exist?(file)
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

            tur.res.headers.set_content_type(mime_type)
            tur.res.headers.set_content_length(file_len)

            begin
              tur.res.send_headers(Tour::TOUR_ID_NOCHECK)

              bufsize = tur.ship.protocol_handler.max_res_packet_data_size
              agt = GrandAgent.get(tur.ship.agent_id)

              f = File.open(file, "rb")
              rd = IORudder.new(f)

              case(BayServer.harbor.file_multiplexer)

              when Harbor::MULTIPLEXER_TYPE_SPIDER
                mpx = agt.spider_multiplexer

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

              send_file_ship.init(rd, tp, tur)
              sid = send_file_ship.ship_id

              tur.res.set_consume_listener do |len, resume|
                if resume
                  send.resume_read(sid)
                end
              end

              mpx.add_rudder_state(rd, RudderState.new(rd, tp))
              mpx.req_read(rd)

            rescue IOError => e
              BayLog.error_e(e)
              raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR, file)
            end

          end


        end
      end
    end
  end
end
