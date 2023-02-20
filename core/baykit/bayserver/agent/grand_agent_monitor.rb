require 'fcntl'
require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/util/io_util'

module Baykit
  module BayServer
    module Agent
      class GrandAgentMonitor
        include Baykit::BayServer::Util

        class << self
          attr :num_agents
          attr :cur_id
          attr :monitors
          attr :finale
        end

        @num_agents = 0
        @cur_id = 0
        @monitors = {}
        @finale = false

        attr :agent_id
        attr :anchorable
        attr :communication_channel

        def initialize(agt_id, anchorable, com_channel)
          @agent_id = agt_id
          @anchorable = anchorable
          @communication_channel = com_channel
        end

        def to_s()
          return "Monitor##{@agent_id}"
        end

        def on_readable()
          begin
            res = IOUtil.read_int32(@communication_channel)
            if res == nil || res == GrandAgent::CMD_CLOSE
              BayLog.debug("%s read Close", self)
              close()
              GrandAgentMonitor.agent_aborted(@agent_id, @anchorable)
            else
              BayLog.debug("%s read OK: %d", self, res)
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
          BayLog.debug("%s send command %s ch=%s", self, cmd, @communication_channel)
          IOUtil.write_int32(@communication_channel, cmd)
        end

        def close()
          @communication_channel.close()
        end

        ########################################
        # Class methods
        ########################################

        def self.init(num_agents)
          @num_agents = num_agents
          @num_agents.times do
            add(true)
          end
        end

        def self.add(anchoroable)
          @cur_id = @cur_id + 1
          agt_id = @cur_id
          if agt_id > 100
            BayLog.error("Too many agents started")
            exit(1)
          end

          if BayServer.harbor.multi_core
            new_argv = BayServer.commandline_args.dup
            new_argv.insert(0, "ruby")
            new_argv << "-agentid=" + agt_id.to_s

            server = TCPServer.open("localhost", 0)
            #BayLog.info("port=%d", server.local_address.ip_port)
            new_argv << "-monitor_port=" + server.local_address.ip_port.to_s

            child = spawn(ENV, new_argv.join(" "))
            BayLog.debug("Process spawned cmd=%s pid=%d", new_argv, child)

            client_socket = server.accept()
            server.close()

          else

            pair = Socket.socketpair(Socket::AF_INET, Socket::SOCK_STREAM, 0)
            client_socket = pair[0]
            GrandAgent.add(agt_id, anchoroable)

            # Agents run on single core (thread mode)
            Thread.new() do
              agt = GrandAgent.get(agt_id)
              agt.run_command_receiver(pair[1])
              agt.run()
            end

          end

          @monitors[agt_id] =
            GrandAgentMonitor.new(
              agt_id,
              anchoroable,
              client_socket)
        end

        def self.agent_aborted(agt_id, anchorable)
          BayLog.info(BayMessage.get(:MSG_GRAND_AGENT_SHUTDOWN, agt_id))

          @monitors.delete(agt_id)

          if not @finale
            if @monitors.length < @num_agents
              begin
                if !BayServer.harbor.multi_core
                  GrandAgent.add(-1, anchorable)
                end
                add(anchorable)
              rescue => e
                BayLog.error_e(e)
              end
            end
          end
        end
      end
    end
  end
end

