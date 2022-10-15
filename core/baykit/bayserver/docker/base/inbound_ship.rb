require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/watercraft/ship'
require 'baykit/bayserver/tours/package'

module Baykit
  module BayServer
    module Docker
      module Base
        class InboundShip < Baykit::BayServer::WaterCraft::Ship

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Util

          # class variables
          class << self
            attr :err_counter
          end
          @err_counter = Counter.new()

          MAX_TOURS = 128

          attr :port_docker

          attr :tour_store
          attr_accessor :need_end
          attr :socket_timeout_sec
          attr :lock
          attr :active_tours

          def initialize()
            super
            @lock = Monitor.new()
            @active_tours = []
          end

          def to_s
            return "#{@agent} ship##{@ship_id}/#{@object_id}[#{protocol()}]"
          end

          def init_inbound(skt, agt, postman, port, proto_hnd)
            self.init(skt, agt, postman)
            @port_docker = port
            @socket_timeout_sec = @port_docker.timeout_sec >= 0 ? @port_docker.timeout_sec : BayServer.harbor.socket_timeout_sec
            @tour_store = TourStore.get_store(agt.agent_id)
            set_protocol_handler(proto_hnd)
          end

          ######################################################
          # Implements Reusable
          ######################################################

          def reset()
            super
            @lock.synchronize do
              if !@active_tours.empty?
                raise Sink.new("%s There are some running tours", self)
              end
            end
            @need_end = false
          end

          ######################################################
          # Other methods
          ######################################################

          def get_tour(tur_key)
            tur = nil
            store_key = InboundShip.uniq_key(@ship_id, tur_key)
            @lock.synchronize do
              tur = @tour_store.get(store_key)
              if tur == nil
                tur = @tour_store.rent(store_key, false)
                if tur == nil
                  return nil
                end
                tur.init(tur_key, self)
                @active_tours.append(tur)
              end
            end
            return tur
          end

          def get_error_tour
            tur_key = InboundShip.err_counter.next()
            store_key = InboundShip.uniq_key(@ship_id, -tur_key)
            tur = @tour_store.rent(store_key, true)
            tur.init(-tur_key, self)
            @active_tours.append(tur)
            return tur
          end

          def send_headers(check_id, tur)
            check_ship_id(check_id)

            if tur.zombie? || tur.aborted?
              # Don't send peer any data
              return
            end

            handled = false
            if !tur.error_handling && tur.res.headers.status >= 400
              trouble = BayServer.harbor.trouble
              if trouble != nil
                cmd = trouble.find(tur.res.headers.status)
                if cmd != nil
                  err_tour = get_error_tour
                  err_tour.req.uri = cmd.target
                  tur.req.headers.copy_to(err_tour.req.headers)
                  tur.res.headers.copy_to(err_tour.res.headers)
                  err_tour.req.remote_port = tur.req.remote_port
                  err_tour.req.remote_address = tur.req.remote_address
                  err_tour.req.server_address = tur.req.server_address
                  err_tour.req.server_port = tur.req.server_port
                  err_tour.req.server_name = tur.req.server_name
                  err_tour.res.header_sent = tur.res.header_sent
                  tur.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ZOMBIE)
                  case cmd.method
                  when :GUIDE
                    err_tour.go
                  when :TEXT
                    @protocol_handler.send_headers(err_tour)
                    data = cmd.target
                    err_tour.res.send_content(Tour::TOUR_ID_NOCHECK, data, 0, data.length)
                    err_tour.end_content(Tour::TOUR_ID_NOCHECK)
                  when :REROUTE
                    err_tour.res.send_http_exception(Tour::TOUR_ID_NOCHECK, HttpException.moved_temp(cmd.target))
                  end
                  handled = true
                end
              end
            end
            if !handled
              @port_docker.additional_headers.each do |nv|
                tur.res.headers.add(nv[0], nv[1])
              end
              begin
                @protocol_handler.send_res_headers(tur)
              rescue IOError => e
                BayLog.debug_e(e, "%s abort: %s", tur, e)
                tur.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ABORTED)
                raise e
              end
            end
          end

          def send_redirect(check_id, tur, status, location)
            check_ship_id(check_id)

            hdr = tur.res.headers
            hdr.status = status
            hdr.set(Headers::LOCATION, location)

            body = "<H2>Document Moved.</H2><BR>" + "<A HREF=\"" + location + "\">" + location + "</A>"

            send_error_content(check_id, tur, body)
          end

          def send_res_content(check_id, tur, bytes, ofs, len, &callback)

            BayLog.debug("%s send_res_content bytes: %d", self, len)

            check_ship_id(check_id)

            if tur.zombie? || tur.aborted?
              # Don't send peer any data
              return
            end

            max_len = @protocol_handler.max_res_packet_data_size();
            if len > max_len
              send_res_content(Tour::TOUR_ID_NOCHECK, tur, bytes, ofs, max_len)
              send_res_content(Tour::TOUR_ID_NOCHECK, tur, bytes, ofs + max_len, len - max_len, &callback)
            else
              begin
                @protocol_handler.send_res_content(tur, bytes, ofs, len, &callback)
              rescue IOError => e
                BayLog.debug_e(e, "%s abort: %s", tur, e)
                tur.change_state(Tour::TOUR_ID_NOCHECK, Tour::TourState::ABORTED)
                raise e
              end
            end
          end

          def send_end_tour(chk_ship_id, chk_tour_id, tur, &callback)
            @lock.synchronize do
              check_ship_id(chk_ship_id)
              BayLog.debug("%s sendEndTour: %s state=%s", self, tur, tur.state)

              if tur.zombie? || tur.aborted?
                # Don't send peer any data. Do nothing
                BayLog.debug("%s Aborted or zombie tour. do nothing: %s state=%s", self, tur, tur.state)
                tur.change_state(chk_tour_id, Tour.TourState.ENDED)
                callback.call()
              else
                if !tur.valid?
                  raise Sink.new("Tour is not valid")
                end
                keep_alive = false
                if tur.req.headers.get_connection() == Headers::CONNECTION_KEEP_ALIVE
                  keep_alive = true
                  if keep_alive
                    res_conn = tur.res.headers.get_connection()
                    keep_alive = (res_conn == Headers::CONNECTION_KEEP_ALIVE) ||
                      (res_conn == Headers::CONNECTION_UNKOWN)
                  end
                  if keep_alive
                    if tur.res.headers.content_length() < 0
                      keep_alive = false
                    end
                  end
                end

                tur.change_state(chk_tour_id, Tour::TourState::ENDED)

                @protocol_handler.send_end_tour(tur, keep_alive, &callback)
              end
            end
          end

          def send_error(check_id, tour, status, message, e)

            check_ship_id(check_id)

            BayLog.debug("%s send error: status=%d, message=%s ex=%s", self, status, message, e == nil ? "" : e.message)

            if e != nil
              BayLog.error_e(e)
            end

            # Create body
            str = HttpStatus.description(status)

            # print status
            body = StringUtil.alloc(8192)

            body << "<h1>" << status.to_s << " " << str << "</h1>\r\n"

            # print message
            #if message != nil && BayLog.debug_mode?
            #  body << message
            #end

            # print stack trace
            #if e != nil && BayLog.debug_mode?
            #  body << "<P><HR><P>\r\n"
            #  body << "<pre>\r\n"
            #  e.backtrace.each do |item|
            #    body << item << "\r\n"
            #  end
            #  body << "</pre>"
            #end

            tour.res.headers.status = status
            send_error_content(check_id, tour, body)
          end



          def end_ship()
            BayLog.debug("%s endShip", self)
            @port_docker.return_protocol_handler(@agent, @protocol_handler)
            @port_docker.return_ship(self)
          end


          def abort_tours()
            return_list = []

            # Abort tours
            @active_tours.each do |tur|
              if tur.valid?
                BayLog.debug("%s is valid, abort it: stat=%s", tur, tur.state)
                if tur.req.abort()
                  return_list << tur
                end
              end
            end

            return_list.each do |tur|
              return_tour(tur)
            end
          end

          protected
          def send_error_content(check_id, tour, content)

            #Get charset
            charset = tour.res.charset

            # Set content type
            if StringUtil.set? charset
              tour.res.headers.set_content_type("text/html charset=" + charset)
            else
              tour.res.headers.set_content_type("text/html")
            end

            if StringUtil.set? content
              tour.res.headers.set_content_length(content.length)
            end
            send_headers(check_id, tour)

            if StringUtil.set? content
              send_res_content(check_id, tour, content, 0, content.length)
            end
          end


          private

          def self.uniq_key(sip_id, tur_key)
            return sip_id << 32 | (tur_key & 0xffffffff);
          end

          public
          def return_tour(tur)
            BayLog.debug("%s Return tour: %s", self, tur)
            @lock.synchronize do
              if !@active_tours.include?(tur)
                raise Sink.new("Tour is not in acive list: %s", tur);
              end

              tour_store.Return(InboundShip.uniq_key(@ship_id, tur.req.key))
              @active_tours.delete(tur)

              if @need_end && @active_tours.empty?
                end_ship()
              end
            end
          end
        end
      end
    end
  end
end

