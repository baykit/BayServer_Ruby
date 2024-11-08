require 'date'
require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/util/selector'

module Baykit
  module BayServer
    module Agent

        #
        # Channel handler
        #   Sockets or file descriptors are kinds of channel
        #
        class NonBlockingHandler
          include Baykit::BayServer::Agent::TimerHandler # implements
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Util



          attr :agent
          attr :ch_map
          attr :ch_count

          def initialize(ship_agent)
            @agent = ship_agent
            @ch_map = {}
            @ch_count = 0
            @operations = []
            @operations_lock = Monitor.new()

            @agent.add_timer_handler(self)
          end


          def to_s()
            return @agent.to_s()
          end

          ######################################################
          # Implements TimerHandler
          ######################################################

          def on_timer()
            self.close_timeout_sockets()
          end

          ######################################################
          # Custom methods
          ######################################################


          def close_timeout_sockets()

          end

          def add_channel_listener(ch, lis)
            ch_state = ChannelState.new(ch, lis)
            add_channel_state(ch, ch_state)
            ch_state.access()
            return ch_state
          end

          def ask_to_start(ch)
            BayLog.debug("%s askToStart: ch=%s", @agent, ch)

            ch_state = find_channel_state(ch)
            ch_state.accepted = true

          end

          def ask_to_connect(ch, addr)

          end

          def ask_to_read(ch)

          end

          def ask_to_write(ch)

          end

          def ask_to_close(ch)

          end

          def close_all()
            @ch_map.keys().each do |ch|
              st = find_channel_state(ch)
              close_channel(ch, st)
            end
          end


          private



          def close_channel(ch, ch_state)
            BayLog.debug("%s Close chState=%s", @agent, ch_state)

            ch.close()

            if ch_state == nil
              ch_state = find_channel_state(ch)
            end

            if ch_state.accepted and @agent.accept_handler
              agent.accept_handler.on_closed
            end

            if ch_state.listener
              ch_state.listener.on_closed(ch)
            end

            remove_channel_state(ch)

            begin
              @agent.selector.unregister(ch)
            rescue IOError => e
              BayLog.warn_e(e)
            end

          end

          def add_channel_state(ch, ch_state)
            BayLog.trace("%s add skt %s chState=%s", @agent, ch, ch_state);

            @ch_map[ch] = ch_state
            @ch_count += 1
          end

          def remove_channel_state(ch)
            BayLog.trace("%s remove skt %s", @agent, ch);

            @ch_map.delete(ch)
            @ch_count -= 1
          end

          def find_channel_state(ch)
            @ch_map[ch]
          end

          def NonBlockingHandler.op_mode(mode)

          end
        end
    end
  end
end
