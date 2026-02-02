require 'baykit/bayserver/sink'

require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/ships/ship'
require 'baykit/bayserver/tours/package'

module Baykit
  module BayServer
    module Common
        class InboundShip < Baykit::BayServer::Ships::Ship

          include Baykit::BayServer
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Util
          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Ships

          # class variables
          class << self
            attr :err_counter
          end
          @err_counter = Counter.new()

          MAX_TOURS = 128

          attr :port_docker

          attr :protocol_handler
          attr_accessor :need_end
          attr :socket_timeout_sec
          attr :tour_store
          attr :active_tours
          attr :lock

          def initialize()
            super
            @lock = ::Monitor.new
            @active_tours = []
          end

          def to_s
            proto = @protocol_handler != nil ? "[" + @protocol_handler.protocol + "]" : ""
            return "agt##{@agent_id} ship##{@ship_id}/#{@object_id}#{proto}"
          end

          def init_inbound(rd, agt_id, tp, port_dkr, proto_hnd)
            self.init(agt_id, rd, tp)
            @port_docker = port_dkr
            @socket_timeout_sec = @port_docker.timeout_sec >= 0 ? @port_docker.timeout_sec : BayServer.harbor.socket_timeout_sec
            @tour_store = TourStore.get_store(agt_id)
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
          # Implements Ship
          ######################################################

          def notify_handshake_done(proto)
            return NextSocketAction::CONTINUE
          end

          def notify_connect
            raise Sink.new
          end

          def notify_read(buf)
            return @protocol_handler.bytes_received(buf)
          end

          def notify_eof
            BayLog.debug("%s EOF detected", self)
            return NextSocketAction::CLOSE
          end

          def notify_error(e)
            BayLog.debug_e(e, "%s Error notified", self)
          end

          def notify_protocol_error(e)
            BayLog.debug_e(e)
            return tour_handler.on_protocol_error(e)
          end

          def notify_close
            BayLog.debug("%s notifyClose", self)

            abort_tours

            if @active_tours.length > 0
              # cannot close because there are some running tours
              BayLog.debug("%s cannot end ship because there are some running tours (ignore)", self)
              @need_end = true
            else
              end_ship
            end
          end

          def check_timeout(duration_sec)
            if @socket_timeout_sec <= 0
              timeout = false
            elsif @keeping
              timeout = duration_sec >= BayServer.harbor.keep_timeout_sec
            else
              timeout = duration_sec >= @socket_timeout_sec
            end

            BayLog.debug("%s Check timeout: dur=%d, timeout=%s, keeping=%s limit=%d keeplim=%d",
                         self, duration_sec, timeout, @keeping, @socket_timeout_sec, BayServer.harbor.keep_timeout_sec)
            return timeout;
          end

          ######################################################
          # Other methods
          ######################################################

          def set_protocol_handler(proto_handler)
            @protocol_handler = proto_handler
            proto_handler.init(self)
            BayLog.debug("%s protocol handler is set", self)
          end

          def get_tour(tur_key, force=false, rent=true)
            tur = nil
            store_key = InboundShip.uniq_key(@ship_id, tur_key)
            @lock.synchronize do
              tur = @tour_store.get(store_key)
              if tur == nil && rent
                tur = @tour_store.rent(store_key, force)
                if tur == nil
                  return nil
                end
                tur.init(tur_key, self)
                @active_tours.append(tur)
              else
                tur.ship.check_ship_id(@ship_id)
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

            @port_docker.additional_headers.each do |nv|
              tur.res.headers.add(nv[0], nv[1])
            end
            BayLog.debug("%s send_res_headers", tur)
            tour_handler.send_res_headers(tur)
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

            max_len = @protocol_handler.max_res_packet_data_size();
            BayLog.debug("%s max_len=%d", self, max_len)
            if len > max_len
              send_res_content(Ship::SHIP_ID_NOCHECK, tur, bytes, ofs, max_len)
              send_res_content(Ship::SHIP_ID_NOCHECK, tur, bytes, ofs + max_len, len - max_len, &callback)
            else
              tour_handler.send_res_content(tur, bytes, ofs, len, &callback)
            end
          end

          def send_end_tour(chk_ship_id, tur, &callback)
            @lock.synchronize do
              check_ship_id(chk_ship_id)
              BayLog.debug("%s sendEndTour: %s state=%s", self, tur, tur.state)

              if !tur.valid?
                raise Sink.new("Tour is not valid")
              end

              tour_handler.send_end_tour(tur, &callback)
            end
          end

          def send_error(chk_id, tour, status, message, e)

            check_ship_id(chk_id)

            BayLog.info("%s send error: status=%d, message=%s ex=%s", self, status, message, e == nil ? "" : e.message)

            if e != nil
              BayLog.debug_e(e)
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
            send_error_content(chk_id, tour, body)
          end



          def end_ship()
            BayLog.debug("%s endShip", self)
            @port_docker.return_protocol_handler(@agent_id, @protocol_handler)
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

          def tour_handler
            return @protocol_handler.command_handler
          end

          protected
          def send_error_content(chk_id, tour, content)

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
            send_headers(chk_id, tour)

            if StringUtil.set? content
              send_res_content(chk_id, tour, content, 0, content.length)
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

