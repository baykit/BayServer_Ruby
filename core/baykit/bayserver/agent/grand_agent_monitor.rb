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
        attr :send_fd
        attr :recv_fd

        def initialize(agt_id, anchorable, send_fd, recv_fd)
          @agent_id = agt_id
          @anchorable = anchorable
          @send_fd = send_fd
          @recv_fd = recv_fd
        end

        def to_s()
          return "Monitor##{@agent_id}"
        end

        def on_readable()
          begin
            res = IOUtil.read_int32(@recv_fd)
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
          BayLog.debug("%s send command %s pipe=%s", self, cmd, @send_fd)
          IOUtil.write_int32(@send_fd, cmd)
        end

        def close()
          @send_fd.close()
          @recv_fd.close()
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

            no_close_io = {}
            @anchored_port_map.each_key do |ch|
              no_close_io[ch] = ch
              if ports != ""
                ports +=","
              end
              ports += ch.fileno.to_s
            end
            new_argv << "-ports=" + ports

            mon_to_agt_pipe = IO.pipe()
            agt_to_mon_pipe = IO.pipe()
            no_close_io[mon_to_agt_pipe[0]] = mon_to_agt_pipe[0]
            no_close_io[agt_to_mon_pipe[1]] = agt_to_mon_pipe[1]
            new_argv << "-pipe=" + mon_to_agt_pipe[0].fileno.to_s + "," + agt_to_mon_pipe[1].fileno.to_s

            BayLog.info("Process spawned: %s", new_argv.join(" "))
            child = spawn(ENV, new_argv.join(" "), no_close_io)
            BayLog.info("Process spawned pid=%d", child)

            mon_to_agt_pipe[0].close
            agt_to_mon_pipe[1].close

            @monitors[agt_id] =
              GrandAgentMonitor.new(
                agt_id,
                anchoroable,
                mon_to_agt_pipe[1],
                agt_to_mon_pipe[0])

          else
            p = IO.pipe()
            @monitors[agt_id] =
              GrandAgentMonitor.new(
                agt_id,
                anchoroable,
                mon_to_agt_pipe[1],
                agt_to_mon_pipe[0])
          end

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

