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
          attr :anchored_port_map
          attr :monitors
          attr :finale
        end

        @num_agents = 0
        @cur_id = 0
        @anchored_port_map = []
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

        def self.init(num_agents, anchored_port_map)
          @num_agents = num_agents
          @anchored_port_map = anchored_port_map
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

            ports = ""

            no_close_io = {}  # Port list not to close on spawned
            @anchored_port_map.each_key do |ch|
              no_close_io[ch] = ch
              if ports != ""
                ports +=","
              end
              ports += ch.fileno.to_s
            end
            new_argv << "-ports=" + ports

            server = TCPServer.open("localhost", 0)
            #BayLog.info("port=%d", server.local_address.ip_port)
            new_argv << "-monitor_port=" + server.local_address.ip_port.to_s

            if SysUtil.run_on_windows()
              child = spawn(ENV, new_argv.join(" "))
            else
              child = spawn(ENV, new_argv.join(" "), no_close_io)
            end

            BayLog.debug("Process spawned cmd=%s pid=%d", new_argv, child)

            client_socket = server.accept()
            server.close()

          else

            if SysUtil::run_on_windows()
              pair = Socket.socketpair(Socket::AF_INET, Socket::SOCK_STREAM, 0)
            else
              pair = Socket.socketpair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
            end

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

        def self.reload_cert_all()
          @monitors.values.each { |mon| mon.reload_cert() }
        end

        def self.restart_all()
          old_monitors = @monitors.dup()

          #@agent_count.times {add()}

          old_monitors.values.each { |mon| mon.shutdown() }
        end

        def self.shutdown_all()
          @finale = true
          @monitors.dup().values.each do |mon|
            mon.shutdown()
          end
        end

        def self.abort_all()
          @finale = true
          @monitors.dup().values.each do |mon|
            mon.abort()
          end
          exit(1)
        end

        def self.print_usage_all()
          @monitors.values.each do |mon|
            mon.print_usage()
          end
        end
      end
    end
  end
end

