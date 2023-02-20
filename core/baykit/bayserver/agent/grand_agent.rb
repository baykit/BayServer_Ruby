require 'socket'

require 'baykit/bayserver/sink'
require 'baykit/bayserver/agent/accept_handler'
require 'baykit/bayserver/agent/grand_agent_monitor'
require 'baykit/bayserver/agent/spin_handler'
require 'baykit/bayserver/agent/signal/signal_agent'

require 'baykit/bayserver/train/train_runner'
require 'baykit/bayserver/taxi/taxi_runner'

require 'baykit/bayserver/util/io_util'
require 'baykit/bayserver/util/selector'

module Baykit
  module BayServer
    module Agent
      class GrandAgent
        include Baykit::BayServer
        include Baykit::BayServer::Train
        include Baykit::BayServer::Taxi
        include Baykit::BayServer::Agent::Signal
        include Baykit::BayServer::Util

        module GrandAgentLifecycleListener
          #
          # interface
          #
          #             void add(int agentId);
          #             void remove(int agentId);
          #
        end

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
                  when CMD_RELOAD_CERT
                    @agent.reload_cert()
                  when CMD_MEM_USAGE
                    @agent.print_usage()
                  when CMD_SHUTDOWN
                    @agent.shutdown()
                    @aborted = true
                  when CMD_ABORT
                    IOUtil.write_int32(@write_fd, CMD_OK)
                    @agent.abort()
                    return
                  else
                    BayLog.error("Unknown command: %d", cmd)
                end
                IOUtil.write_int32(@write_fd, CMD_OK)
              rescue IOError => e
                BayLog.debug("%s Read failed (maybe agent shut down): %s", self, e)
              ensure
                BayLog.debug("%s Command ended", self)
              end
            end
          end

          def abort()
            BayLog.debug("%s end", self)
            IOUtil.write_int32(@write_fd, CMD_CLOSE)
          end
        end

        SELECT_TIMEOUT_SEC = 10

        CMD_OK = 0
        CMD_CLOSE = 1
        CMD_RELOAD_CERT = 2
        CMD_MEM_USAGE = 3
        CMD_SHUTDOWN = 4
        CMD_ABORT = 5

        attr :agent_id
        attr :anchorable
        attr :non_blocking_handler
        attr :spin_handler
        attr :accept_handler
        attr :send_wakeup_pipe
        attr :select_wakeup_pipe
        attr :select_timeout_sec
        attr :max_inbound_ships
        attr :selector
        attr :unanchorable_transporters
        attr :aborted
        attr :command_receiver

        class << self
          attr :agents
          attr :listeners
          attr :monitors
          attr :agent_count
          attr :anchorable_port_map
          attr :unanchorable_port_map
          attr :max_ships
          attr :max_agent_id
          attr :multi_core
          attr :finale
        end
        @agents = []
        @listeners = []
        @monitors = []
        @agent_count = 0
        @anchorable_port_map = {}
        @unanchorable_port_map = {}
        @max_ships = 0
        @max_agent_id = 0
        @multi_core = false
        @finale = false

        def initialize (agent_id, max_ships, anchorable, recv_pipe, send_pipe)
          @agent_id = agent_id
          @anchorable = anchorable

          if @anchorable
            @accept_handler = AcceptHandler.new(self, GrandAgent.anchorable_port_map)
          else
            @accept_handler = nil
          end

          @spin_handler = SpinHandler.new(self)
          @non_blocking_handler = NonBlockingHandler.new(self)

          @select_timeout_sec = SELECT_TIMEOUT_SEC
          @max_inbound_ships = max_ships
          @selector = Selector.new()
          @aborted = false
          @unanchorable_transporters = {}
          @command_receiver = CommandReceiver.new(self, recv_pipe[0], send_pipe[1])

        end


        def to_s()
          return "Agt#" + @agent_id.to_s
        end


        def inspect()
          return to_s
        end

        def run
          BayLog.info(BayMessage.get(:MSG_RUNNING_GRAND_AGENT, self))
          @select_wakeup_pipe = IO.pipe
          @selector.register(@select_wakeup_pipe[0], Selector::OP_READ)
          @selector.register(@command_receiver.read_fd, Selector::OP_READ)

          # Set up unanchorable channel
          for ch in GrandAgent.unanchorable_port_map.keys() do
            port_dkr = GrandAgent.unanchorable_port_map[ch]
            tp = port_dkr.new_transporter(self, ch)
            @unanchorable_transporters[ch] = tp
            @non_blocking_handler.add_channel_listener(ch, tp)
            @non_blocking_handler.ask_to_start(ch)
            if !@anchorable
              @non_blocking_handler.ask_to_read(ch)
            end
          end

          busy = true
          begin
            while not @aborted
              begin
                count = -1

                if @accept_handler
                  test_busy = @accept_handler.ch_count >= @max_inbound_ships
                  if test_busy != busy
                    busy = test_busy
                    if busy
                      @accept_handler.on_busy()
                    else
                      @accept_handler.on_free()
                    end
                  end
                end

                if !busy && @selector.count() == 2
                  # agent finished
                  BayLog.debug("%s Selector has no key", self)
                  break
                end

                if !@spin_handler.empty?
                  timeout = 0
                else
                  timeout = @select_timeout_sec
                end

                #@BayServer.debug("Selecting... read=" + read_list.to_s)
                selected_map = @selector.select(timeout)
                #BayLog.debug("%s selected: %s", self, selected_map)

                processed = @non_blocking_handler.register_channel_ops() > 0

                if selected_map.length == 0
                  # No channel is selected
                  processed |= @spin_handler.process_data()
                end

                selected_map.keys().each do |ch|
                  if ch == @select_wakeup_pipe[0]
                    # Waked up by ask_to_*
                    on_waked_up(ch)
                  elsif ch == @command_receiver.read_fd
                    @command_receiver.on_pipe_readable()
                  elsif @accept_handler && @accept_handler.server_socket?(ch)
                    @accept_handler.on_acceptable(ch)
                  else
                    @non_blocking_handler.handle_channel(ch, selected_map[ch])
                  end
                  processed = true
                end

                if not processed
                  # timeout check
                  @non_blocking_handler.close_timeout_sockets()
                  @spin_handler.stop_timeout_spins()
                end

              rescue => e
                raise e
              end
            end # while

          rescue => e
            BayLog.error_e(e)
            raise e
          ensure
            BayLog.info("%s end", self)
            @command_receiver.abort()
            GrandAgent.listeners.each { |lis| lis.remove(self)}
          end
        end

        def shutdown()
          BayLog.debug("%s shutdown", self)
          if @accept_handler != nil
            @accept_handler.shutdown()
          end
        end

        def abort()
          BayLog.debug("%s abort", self)
          exit(1)
        end

        def reload_cert()
          GrandAgent.anchorable_port_map.values().each do |port|
            if port.secure()
              begin
                port.secure_docker.reload_cert()
              rescue => e
                BayLog.error_e(e)
              end
            end
          end
        end

        def print_usage()
          # print memory usage
          BayLog.info("Agent#%d MemUsage", @agent_id);
          MemUsage.get(@agent_id).print_usage(1);
        end

        def wakeup
          #BayLog.debug("%s wakeup", self)
          IOUtil.write_int32(@select_wakeup_pipe[1], 0)
        end


        private
        def on_waked_up(pipe_fd)
          #BayLog.debug("%s waked up", self)
          val = IOUtil.read_int32(pipe_fd)
        end


        ######################################################
        # class methods
        ######################################################
        def GrandAgent.init(count, anchorable_port_map, unanchorable_port_map, max_ships, multi_core)
          @agent_count = count
          @anchorable_port_map = anchorable_port_map
          @unanchorable_port_map = unanchorable_port_map
          @max_ships = max_ships
          @multi_core = multi_core
          if GrandAgent.unanchorable_port_map.length > 0
            add(false)
          end
          count.times do
            add(true)
          end
        end

        def GrandAgent.get(id)
          @agents.each do |agt|
            if agt.id = id
              return agt
            end
          end
          return nil
        end

        def GrandAgent.add(anchorable)
          @max_agent_id += 1
          agt_id = @max_agent_id
          send_pipe = IO.pipe()
          recv_pipe = IO.pipe()

          if @multi_core

            # Agents run on multi core (process mode)
            pid = Process.fork do
              # train runners and tax runners run in the new process
              invoke_runners()

              agt = GrandAgent.new(agt_id, BayServer.harbor.max_ships, anchorable, send_pipe, recv_pipe)
              @agents.append(agt)
              @listeners.each { |lis| lis.add(agt)}

              agent_thread = Thread.new() do
                agt.run
              end

              # Main thread sleeps until agent finished
              agent_thread.join()
            end

            mon = GrandAgentMonitor.new(agt_id, anchorable, send_pipe, recv_pipe)
            @monitors.append(mon)

          else
            invoke_runners()

            # Agents run on single core (thread mode)
            agent_thread = Thread.new() do
              agt = GrandAgent.new(agt_id, BayServer.harbor.max_ships, anchorable, send_pipe, recv_pipe)
              @agents.append(agt)
              @listeners.each { |lis| lis.add(agt)}
              agt.run
            end

            mon = GrandAgentMonitor.new(agt_id, anchorable, send_pipe, recv_pipe)
            @monitors.append(mon)

          end
        end

        def GrandAgent.reload_cert_all()
          @monitors.each { |mon| mon.reload_cert() }
        end

        def GrandAgent.restart_all()
          old_monitors = @monitors.dup()

          #@agent_count.times {add()}

          old_monitors.each { |mon| mon.shutdown() }
        end

        def GrandAgent.shutdown_all()
          @finale = true
          @monitors.dup().each do |mon|
            mon.shutdown()
          end
        end

        def GrandAgent.abort_all()
          @finale = true
          @monitors.dup().each do |mon|
            mon.abort()
          end
          exit(1)
        end

        def GrandAgent.print_usage_all()
          @monitors.each do |mon|
            mon.print_usage()
          end
        end

        def GrandAgent.add_lifecycle_listener(lis)
          @listeners.append(lis)
        end


        def GrandAgent.agent_aborted(agt_id, anchorable)
          BayLog.info(BayMessage.get(:MSG_GRAND_AGENT_SHUTDOWN, agt_id))

          @agents.delete_if do |agt|
            agt.agent_id == agt_id
          end

          @monitors.delete_if do |mon|
            mon.agent_id == agt_id
          end

          if not @finale
            if @agents.length < @agent_count
              add(anchorable)
            end
          end
        end

        private
        #
        # Run train runners and taxi runners inner process
        #   ALl the train runners and taxi runners run in each process (not thread)
        #
        def GrandAgent.invoke_runners()
          n = BayServer.harbor.train_runners
          TrainRunner.init(n)

          n = BayServer.harbor.taxi_runners
          TaxiRunner.init(n)

        end
      end
    end
  end
end
