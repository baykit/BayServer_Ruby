
require 'baykit/bayserver/agent/monitor/grand_agent_monitor'
require 'baykit/bayserver/ships/ship'

module Baykit
  module BayServer
    module Agent
      #
      # CommandReceiver receives commands from GrandAgentMonitor
      #
      class CommandReceiver < Baykit::BayServer::Ships::Ship

        include Baykit::BayServer
        include Baykit::BayServer::Agent::Monitor
        include Baykit::BayServer::Util


        def init(agt_id, rd, tp)
          super
        end

        def to_s()
          return "ComReceiver##{@agent_id}"
        end

        #########################################
        # Implements Ship
        #########################################
        def notify_handshake_done(proto)
          raise Sink.new
        end

        def notify_connect
          raise Sink.new
        end

        def notify_read(buf)
          BayLog.debug("%s notify_read", self)
          cmd = GrandAgentMonitor.buffer_to_int(buf)
          on_read_command(cmd)
          return NextSocketAction::CONTINUE
        end

        def notify_eof
          BayLog.debug("%s notify_eof", self)
          return NextSocketAction::CLOSE
        end

        def notify_error(e)
          BayLog.error_e(e)
        end

        def notify_protocol_error(e)
          raise Sink.new
        end

        def notify_close
        end

        def check_timeout(duration_sec)
          return false
        end

        #########################################
        # Custom methods
        #########################################
        def on_read_command(cmd)
          agt = GrandAgent.get(@agent_id)

          BayLog.debug("%s receive command %d rd=%s", self, cmd, @rudder)
          begin
            if cmd == nil
              BayLog.debug("%s pipe closed", self)
              agt.abort_agent
            else
              case cmd
              when GrandAgent::CMD_RELOAD_CERT
                agt.reload_cert
              when GrandAgent::CMD_MEM_USAGE
                agt.print_usage
              when GrandAgent::CMD_SHUTDOWN
                agt.req_shutdown
              when GrandAgent::CMD_ABORT
                send_command_to_monitor(agt, GrandAgent::CMD_OK, true)
                agt.abort_agent
                return
              when GrandAgent::CMD_CATCHUP
                agt.catch_up
                return
              else
                BayLog.error("Unknown command: %d", cmd)
              end

              send_command_to_monitor(agt, GrandAgent::CMD_OK, false)
            end
          rescue IOError => e
            BayLog.error_e(e, "%s Command thread aborted(end)", self)
            close
          ensure
            BayLog.debug("%s Command ended", self)
          end
        end

        def send_command_to_monitor(agt, cmd, sync)
          buf = GrandAgentMonitor.int_to_buffer(cmd)
          if sync

          end
        end

        def end
          BayLog.debug("%s send end to monitor", self)
          begin
            send_command_to_monitor(nil, GrandAgent::CMD_CLOSE, true)
          rescue IOError => e
            BayLog.error_e(e)
          end

          close
        end

        def close
          if @closed
            return
          end

          @rudder.close
          @closed = true
        end

      end
    end
  end
end
