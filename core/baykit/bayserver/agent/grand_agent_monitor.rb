require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/util/io_util'

module Baykit
  module BayServer
    module Agent
      class GrandAgentMonitor
        include Baykit::BayServer::Util

        attr :agent_id
        attr :anchorable
        attr :send_pipe
        attr :recv_pipe

        def initialize(agt_id, anchorable, send_pipe, recv_pipe)
          @agent_id = agt_id
          @anchorable = anchorable
          @send_pipe = send_pipe
          @recv_pipe = recv_pipe
        end

        def to_s()
          return "Monitor##{@agent_id}"
        end

        def on_readable()
          begin
            while true
              res = IOUtil.read_int32(@recv_pipe[0])
              if res == nil || res == GrandAgent::CMD_CLOSE
                BayLog.debug("%s read Close", self)
                GrandAgent.agent_aborted(@agent_id, @anchorable)
              else
                BayLog.debug("%s read OK: %d", self, res)
              end
            end
          rescue IO::WaitReadable
            #BayLog.debug("%s no data", self)
          end
        end

        def shutdown()
          BayLog.debug("%s send shutdown command", self)
          send(GrandAgent::CMD_SHUTDOWN)
        end

        def abort()
          BayLog.debug("%s Send abort command", self)
          send(GrandAgent::CMD_ABORT)
        end

        def reload_cert()
          BayLog.debug("%s Send reload command", self)
          send(GrandAgent::CMD_RELOAD_CERT)
        end

        def print_usage()
          BayLog.debug("%s Send mem_usage command", self)
          send(GrandAgent::CMD_MEM_USAGE)
        end

        def send(cmd)
          BayLog.debug("%s send command %s pipe=%s", self, cmd, @send_pipe[1])
          IOUtil.write_int32(@send_pipe[1], cmd)
        end

        def close()
          @send_pipe[0].close()
          @send_pipe[1].close()
          @recv_pipe[0].close()
          @recv_pipe[1].close()
        end
      end
    end
  end
end

