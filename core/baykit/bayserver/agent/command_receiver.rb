


module Baykit
  module BayServer
    module Agent
      #
      # CommandReceiver receives commands from GrandAgentMonitor
      #
      class CommandReceiver
        include Baykit::BayServer::Util
        attr :agent
        attr :read_fd
        attr :write_fd
        attr :aborted

        def initialize(agent, read_fd, write_fd)
          @agent = agent
          @read_fd = read_fd
          @write_fd = write_fd
          @aborted = false
        end

        def to_s()
          return "ComReceiver##{@agent.agent_id}"
        end

        def on_pipe_readable()
          cmd = IOUtil.read_int32(@read_fd)
          if cmd == nil
            BayLog.debug("%s pipe closed: %d", self, @read_fd)
            @agent.abort()
          else
            BayLog.debug("%s receive command %d pipe=%d", self, cmd, @read_fd)
            begin
              case cmd
              when GrandAgent::CMD_RELOAD_CERT
                @agent.reload_cert()
              when GrandAgent::CMD_MEM_USAGE
                @agent.print_usage()
              when GrandAgent::CMD_SHUTDOWN
                @agent.shutdown()
                @aborted = true
              when GrandAgent::CMD_ABORT
                IOUtil.write_int32(@write_fd, GrandAgent::CMD_OK)
                @agent.abort()
                return
              else
                BayLog.error("Unknown command: %d", cmd)
              end
              IOUtil.write_int32(@write_fd, GrandAgent::CMD_OK)
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
            IOUtil.write_int32(@write_fd, GrandAgent::CMD_CLOSE)
          rescue => e
            BayLog.error_e(e, "%s Write error", @agent);
          end
          close()
        end

        def close()
          @read_fd.close()
          @write_fd.close()
        end

      end
    end
  end
end
