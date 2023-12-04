


module Baykit
  module BayServer
    module Agent
      #
      # CommandReceiver receives commands from GrandAgentMonitor
      #
      class CommandReceiver
        include Baykit::BayServer::Util
        attr :agent
        attr :communication_channel
        attr :aborted

        def initialize(agent, com_ch)
          @agent = agent
          @communication_channel = com_ch
          @aborted = false
        end

        def to_s()
          return "ComReceiver##{@agent.agent_id}"
        end

        def on_pipe_readable()
          cmd = IOUtil.read_int32(@communication_channel)
          if cmd == nil
            BayLog.debug("%s pipe closed: %d", self, @communication_channel)
            @agent.abort_agent()
          else
            BayLog.debug("%s receive command %d pipe=%d", self, cmd, @communication_channel)
            begin
              case cmd
              when GrandAgent::CMD_RELOAD_CERT
                @agent.reload_cert()
              when GrandAgent::CMD_MEM_USAGE
                @agent.print_usage()
              when GrandAgent::CMD_SHUTDOWN
                @agent.req_shutdown()
                @aborted = true
              when GrandAgent::CMD_ABORT
                IOUtil.write_int32(@communication_channel, GrandAgent::CMD_OK)
                @agent.abort_agent()
                return
              else
                BayLog.error("Unknown command: %d", cmd)
              end
              IOUtil.write_int32(@communication_channel, GrandAgent::CMD_OK)
            rescue IOError => e
              BayLog.debug("%s Read failed (maybe agent shut down): %s", self, e)
            ensure
              BayLog.debug("%s Command ended", self)
            end
          end
        end

        def end()
          BayLog.debug("%s end", self)
          begin
            IOUtil.write_int32(@communication_channel, GrandAgent::CMD_CLOSE)
          rescue => e
            BayLog.error_e(e, "%s Write error", @agent);
          end
          close()
        end

        def close()
          @communication_channel.close()
        end

      end
    end
  end
end
