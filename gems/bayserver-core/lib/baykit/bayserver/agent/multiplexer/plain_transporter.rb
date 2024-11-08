require 'baykit/bayserver/agent/multiplexer/transporter'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/agent/next_socket_action'

module Baykit
  module BayServer
    module Agent
      module Multiplexer
        class PlainTransporter
          include Transporter   # Implements
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Util

          attr :multiplexer
          attr :server_mode
          attr :trace_ssl
          attr :read_buffer_size
          attr :ship
          attr :closed

          def initialize(mpx, sip, server_mode, bufsiz, trace_ssl)
            @multiplexer = mpx
            @ship = sip
            @server_mode = server_mode
            @trace_ssl = trace_ssl
            @read_buffer_size = bufsiz
            @closed = false
          end

          def to_s
            return "tp[#{@ship}]"
          end

          #########################################
          # Implements Transporter
          #########################################

          def init

          end

          def on_connect(rd)
            BayLog.trace("%s onConnect", self)

            return @ship.notify_connect
            ;
          end

          def on_read(rd, buf, adr)
            BayLog.debug("%s onRead", self)

            if buf.length == 0
              return @ship.notify_eof
            else
              begin
                return @ship.notify_read(buf)

              rescue UpgradeException => e
                BayLog.debug("%s Protocol upgrade", @ship)
                return @ship.notify_read(buf)

              rescue ProtocolException => e
                close = @ship.notify_protocol_error(e)
                if !close && @server_mode
                  return NextSocketAction::CONTINUE
                else
                  return NextSocketAction::CLOSE
                end

              rescue IOError => e
                # IOError which occur in notifyRead must be distinguished from
                # IOError which occur in handshake or readNonBlock.
                on_error(rd, e)
                return NextSocketAction::CLOSE
              end
            end
          end

          def on_error(rd, e)
            @ship.notify_error(e)
          end

          def on_closed(rd)
            @ship.notify_close
          end

          def req_connect(rd, adr)
            @multiplexer.req_connect(rd, adr)
          end

          def req_read(rd)
            @multiplexer.req_read(rd)
          end

          def req_write(rd, buf, adr, tag, &lis)
            @multiplexer.req_write(rd, buf, adr, tag, lis)
          end

          def req_close(rd)
            @closed = true
            @multiplexer.req_close(rd)
          end

          def check_timeout(rd, duration_sec)
            return @ship.check_timeout(duration_sec)
          end

          def get_read_buffer_size
            return @read_buffer_size
          end

          def print_usage(indent)
          end


          #########################################
          # Custom methods
          #########################################
          def secure()
            return false
          end
        end
      end
    end
  end
end


