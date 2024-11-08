require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/agent/transporter/data_listener'
require 'baykit/bayserver/ships/ship'
require 'baykit/bayserver/tours/package'

module Baykit
  module BayServer
    module Docker
      module Base
        class InboundDataListener

          include Baykit::BayServer::Agent::Transporter::DataListener   # implements
          include Baykit::BayServer::Agent

          attr :ship

          def initialize(sip)
            @ship = sip
          end

          def to_s
            return @ship.to_s
          end

          ######################################################
          # Implements DataListener
          ######################################################

          def notify_connect()
            raise Sink.new()
          end

          def notify_handshake_done(protocol)
            BayLog.trace("%s notify_handshake_done: proto=%s", self, protocol)
            return NextSocketAction::CONTINUE
          end

          def notify_read(buf, adr)
            BayLog.trace("%s notify_read", self)
            return @ship.protocol_handler.bytes_received(buf)
          end

          def notify_eof()
            BayLog.trace("%s notify_eof", self)
            return NextSocketAction::CLOSE
          end

          def notify_protocol_error(err)
            BayLog.trace("%s notify_protocol_error", self)
            if BayLog.debug_mode?
              BayLog.error_e(err)
            end
            return @ship.protocol_handler.send_req_protocol_error(err)
          end

          def notify_close
            BayLog.debug("%s notify_close", self)

            @ship.abort_tours()

            if !@ship.active_tours.empty?
              # cannot close because there are some running tours
              BayLog.debug("%s cannot end ship because there are some running tours (ignore)", self)
              @ship.need_end = true
            else
              @ship.end_ship()
            end

          end

          def check_timeout(duration_sec)
            if @ship.socket_timeout_sec <= 0
              timeout = false;
            elsif @ship.keeping
              timeout = duration_sec >= BayServer.harbor.keep_timeout_sec
            else
              timeout = duration_sec >= @ship.socket_timeout_sec
            end
            BayLog.debug("%s Check timeout: dur=%d timeout=%s, keeping=%s, limit=%d",
                         self, duration_sec, timeout, @ship.keeping, @ship.socket_timeout_sec)
            return timeout
          end

        end
      end
    end
  end
end

