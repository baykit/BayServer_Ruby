require 'socket'

require 'baykit/bayserver/sink'
require 'baykit/bayserver/agent/accept_handler'
require 'baykit/bayserver/agent/command_receiver'
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
          attr :agent_count
          attr :anchorable_port_map
          attr :unanchorable_port_map
          attr :max_ships
          attr :max_agent_id
          attr :multi_core
        end

        # Class variables
        @agent_count = 0
        @max_agent_id = 0
        @max_ships = 0
        @multi_core = false

        @agents = []
        @listeners = []

        @anchorable_port_map = {}
        @unanchorable_port_map = {}
        @finale = false

        def initialize (agent_id, max_ships, anchorable)
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
          @selector.register(@command_receiver.communication_channel, Selector::OP_READ)

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
                  elsif ch == @command_receiver.communication_channel
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
            abort_agent(nil, 0)
          end
        end

        def shutdown()
          BayLog.debug("%s shutdown", self)
          if @accept_handler != nil
            @accept_handler.shutdown()
          end
          @aborted = true
          wakeup()
        end

        def abort_agent(err = nil, status = 1)
          if err
            BayLog.fatal("%s abort", self)
            BayLog.fatal_e(err)
          end

          @command_receiver.end()
          GrandAgent.listeners.each do |lis|
            lis.remove(self)
          end

          GrandAgent.agents.delete(@agent_id)

          if BayServer.harbor.multi_core
            exit(1)
          else
            clean()
          end

          @aborted = true
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

        def run_command_receiver(com_channel)
          @command_receiver = CommandReceiver.new(self, com_channel)
        end

        private
        def on_waked_up(pipe_fd)
          #BayLog.debug("%s waked up", self)
          val = IOUtil.read_int32(pipe_fd)
        end

        def clean()
          @non_blocking_handler.close_all()
          @agent_id = -1
        end

        ######################################################
        # class methods
        ######################################################
        def GrandAgent.init(agt_ids, anchorable_port_map, unanchorable_port_map, max_ships, multi_core)
          @agent_count = agt_ids.length
          @anchorable_port_map = anchorable_port_map
          @unanchorable_port_map = unanchorable_port_map != nil ? unanchorable_port_map : {}
          @max_ships = max_ships
          @multi_core = multi_core

          if(BayServer.harbor.multi_core?)
            agt_ids.each do | agt_id |
              add(agt_id, true)
            end
          end
        end

        def GrandAgent.get(agt_id)
          return @agents[agt_id]
        end

        def self.add(agt_id, anchorable)
          if agt_id == -1
            agt_id = @max_agent_id + 1
          end
          BayLog.debug("Add agent: id=%d", agt_id)
          if agt_id > @max_agent_id
            @max_agent_id = agt_id
          end

          agt = GrandAgent.new(agt_id, @max_ships, anchorable)
          @agents[agt_id] = agt

          @listeners.each do |lis|
            lis.add(agt)
          end
        end

        def GrandAgent.add_lifecycle_listener(lis)
          @listeners.append(lis)
        end
      end
    end
  end
end
