require 'fcntl'
require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/util/io_util'

module Baykit
  module BayServer
    module Agent
      module Monitor
        class GrandAgentMonitor
          include Baykit::BayServer::Util
          include Baykit::BayServer::Rudders

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
          attr :rudder
          attr :child_thread
          attr :child_pid

          def initialize(agt_id, anchorable, rd, child_thread, child_pid)
            @agent_id = agt_id
            @anchorable = anchorable
            @rudder = rd
            @child_thread = child_thread
            @child_pid = child_pid
          end

          def to_s()
            return "Monitor##{@agent_id}"
          end

          def run()
            begin
              while true do
                buf = " " * 4

                n = @rudder.read(buf, 4)
                if n == -1
                  raise EOFError.new()
                end
                if n < 4
                  raise IOError.new("Cannot read int: nbytes=#{n}")
                end
                res = buffer_to_int(buf)
                if res == GrandAgent::CMD_CLOSE
                  BayLog.debug("%s read Close", self)
                  break
                elsif res == GrandAgent::CMD_CATCHUP
                  on_read_catch_up()
                else
                  BayLog.debug("%s read OK: %d", self, res);
                end

              end
            rescue EOFError => e
              BayLog.fatal("Agent terminated")
            rescue Exception => e
              BayLog.fatal_e(e)
            end
          end

          def on_readable()
            begin
              res = IOUtil.read_int32(@communication_channel)
              if res == nil || res == GrandAgent::CMD_CLOSE
                close()
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
            sleep(0.5)  # Lazy implementation
          end

          def send(cmd)
            BayLog.debug("%s send command %s rd=%s", self, cmd, @rudder)
            buf = GrandAgentMonitor.int_to_buffer(cmd)
            @rudder.write(buf)
          end

          def close()
            @rudder.close()
          end

          def on_read_catch_up()

          end
          def req_catch_up()

          end

          def agent_aborted()
            BayLog.info(BayMessage.get(:MSG_GRAND_AGENT_SHUTDOWN, @agent_id))

            if @child_pid != nil
              begin
                Process.kill("TERM", @child_pid)
              rescue => e
                BayLog.debug_e(e, "Error on killing process")
              end
              Process.wait(@child_pid)
            end
            GrandAgentMonitor.monitors.delete(@agent_id)

            if not GrandAgentMonitor.finale
              if GrandAgentMonitor.monitors.length < GrandAgentMonitor.num_agents
                begin
                  if !BayServer.harbor.multi_core
                    GrandAgent.add(-1, @anchorable)
                  end
                  GrandAgentMonitor.add(@anchorable)
                rescue => e
                  BayLog.error_e(e)
                end
              end
            end
          end

          def start
            @child_thread = Thread.new do
              run()
            end
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
                child_pid = spawn(ENV, new_argv.join(" "))
              else
                child_pid = spawn(ENV, new_argv.join(" "), no_close_io)
              end

              BayLog.debug("Process spawned cmd=%s pid=%d", new_argv, child_pid)

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
              child_thread = Thread.new() do
                agt = GrandAgent.get(agt_id)
                agt.add_command_receiver(IORudder.new(pair[1]))
                agt.start()
              end

            end

            mon =
              GrandAgentMonitor.new(
                agt_id,
                anchoroable,
                IORudder.new(client_socket),
                child_thread,
                child_pid)
            @monitors[agt_id] = mon
            mon.start

          end

          def self.join
            while !@monitors.empty?
              @monitors.values.each do |mon|
                mon.child_thread.join
                mon.agent_aborted
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

          def self.buffer_to_int(buf)
            return buf.unpack("N").first
          end

          def self.int_to_buffer(val)
            return [val].pack("N")
          end

        end
      end
    end
  end
end

