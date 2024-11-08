require 'socket'
require 'objspace'

require 'baykit/bayserver/sink'
require 'baykit/bayserver/agent/command_receiver'
require 'baykit/bayserver/agent/letter'
require 'baykit/bayserver/agent/multiplexer/spider_multiplexer'
require 'baykit/bayserver/agent/multiplexer/spin_multiplexer'
require 'baykit/bayserver/agent/multiplexer/job_multiplexer'
require 'baykit/bayserver/agent/multiplexer/rudder_state'
require 'baykit/bayserver/agent/monitor/grand_agent_monitor'
require 'baykit/bayserver/agent/signal/signal_agent'

require 'baykit/bayserver/docker/harbor'

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
        include Baykit::BayServer::Agent::Multiplexer
        include Baykit::BayServer::Docker
        include Baykit::BayServer::Util

        SELECT_TIMEOUT_SEC = 10

        CMD_OK = 0
        CMD_CLOSE = 1
        CMD_RELOAD_CERT = 2
        CMD_MEM_USAGE = 3
        CMD_SHUTDOWN = 4
        CMD_ABORT = 5
        CMD_CATCHUP = 6

        attr :agent_id
        attr :anchorable
        attr :net_multiplexer
        attr :job_multiplexer
        attr :taxi_multiplexer
        attr :spin_multiplexer
        attr :spider_multiplexer
        attr :job_multiplexer
        attr :recipient

        attr :send_wakeup_pipe
        attr :max_inbound_ships
        attr :unanchorable_transporters
        attr :aborted
        attr :command_receiver
        attr :timer_handlers
        attr :last_timeout_check
        attr :letter_queue
        attr :letter_queue_lock
        attr :postpone_queue
        attr :postpone_queue_lock

        class << self
          attr :agents
          attr :listeners
          attr :agent_count
          attr :max_ships
          attr :max_agent_id
        end

        # Class variables
        @agent_count = 0
        @max_agent_id = 0
        @max_ships = 0

        @agents = []
        @listeners = []

        @finale = false

        def initialize (agent_id, max_ships, anchorable)
          @agent_id = agent_id
          @max_inbound_ships = max_ships
          @anchorable = anchorable
          @timer_handlers = []
          @select_timeout_sec = SELECT_TIMEOUT_SEC
          @aborted = false
          @letter_queue = []
          @letter_queue_lock = Mutex.new
          @postpone_queue = []
          @postpone_queue_lock = Mutex.new

          @spider_multiplexer = SpiderMultiplexer.new(self, anchorable)
          @spin_multiplexer = SpinMultiplexer.new(self)
          @job_multiplexer = JobMultiplexer.new(self, anchorable)

          case BayServer.harbor.recipient
          when Harbor::RECIPIENT_TYPE_SPIDER
            @recipient = @spider_multiplexer

          when Harbor::RECIPIENT_TYPE_PIPE
            raise NotImplementedError.new
          end

          case BayServer.harbor.net_multiplexer
          when Harbor::MULTIPLEXER_TYPE_SPIDER
            @net_multiplexer = @spider_multiplexer

          when Harbor::MULTIPLEXER_TYPE_JOB
            @net_multiplexer = @job_multiplexer

          when Harbor::MULTIPLEXER_TYPE_PIGEON, Harbor::MULTIPLEXER_TYPE_SPIN,
               Harbor::MULTIPLEXER_TYPE_TAXI, Harbor::MULTIPLEXER_TYPE_TRAIN

            raise Sink.new("Multiplexer not supported: %s", Harbor.get_multiplexer_type_name(BayServer.harbor.net_multiplexer))
          end

          @last_timeout_check = 0
        end


        def to_s()
          return "agt#" + @agent_id.to_s
        end


        def inspect
          return to_s
        end

        #########################################
        # Custom methods
        #########################################
        def start
          Thread.new do
            run
          end
        end

        def run
          BayLog.info(BayMessage.get(:MSG_RUNNING_GRAND_AGENT, self))

          if @net_multiplexer.is_non_blocking
            BayLog.info("rec=%s", @command_receiver)
            @command_receiver.rudder.set_non_blocking
          end

          @net_multiplexer.req_read(@command_receiver.rudder)

          if @anchorable
            # Adds server socket channel of anchorable ports
            BayServer.anchorable_port_map.keys.each do |rd|
              if @net_multiplexer.is_non_blocking
                rd.set_non_blocking
              end
              @net_multiplexer.add_rudder_state(rd, RudderState.new(rd))
            end
          end

          # Set up unanchorable channel
=begin
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
=end

          busy = true
          begin
            while true

              test_busy = @net_multiplexer.is_busy
              if test_busy != busy
                busy = test_busy
                if busy
                  @net_multiplexer.on_busy
                else
                  @net_multiplexer.on_free
                end
              end

              if not @spin_multiplexer.is_empty
                # If "SpinHandler" is running, the select function does not block.
                received = @recipient.receive(false)
                @spin_multiplexer.process_data
              else
                received = @recipient.receive(true)
              end

              if @aborted
                BayLog.info("%s aborted by another thread", self)
                break;
              end

              if @spin_multiplexer.is_empty && @letter_queue.empty?
                # timed out
                # check per 10 seconds
                if Time.now.tv_sec - @last_timeout_check >= 10
                  ring
                end
              end

              while !@letter_queue.empty?
                let = nil
                @letter_queue_lock.synchronize do
                  let = @letter_queue.shift
                end

                case let.type
                when Letter::ACCEPTED
                  on_accept(let)
                when Letter::CONNECTED
                  on_connect(let)
                when Letter::READ
                  on_read(let)
                when Letter::WROTE
                  on_wrote(let)
                when Letter::CLOSEREQ
                  on_close_req(let)
                end
              end
            end # while

          rescue Exception => e
            BayLog.fatal_e(e)
          ensure
            BayLog.info("%s end", self)
            shutdown
          end
        end



        def abort_agent
          BayLog.info("%s abort", self)

          if BayServer.harbor.multi_core
            exit(1)
          end
        end

        def req_shutdown
          @aborted = true
          @recipient.wakeup
        end


        def print_usage
          # print memory usage
          BayLog.info("%s MemUsage", self)
          BayLog.info("  Ruby version: %s", RUBY_VERSION)
          memsize = ObjectSpace.memsize_of_all
          # formatted by comma
          msize_comma = memsize.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse.then do |str|
            str[0] == ',' ? str[1..-1] : str
          end
          BayLog.info("  Total object size: %s bytes", msize_comma)
          MemUsage.get(@agent_id).print_usage(1)
        end


        def add_timer_handler(handler)
          @timer_handlers << handler
        end

        def remove_timer_handler(handler)
          @timer_handlers.delete(handler)
        end

        def add_command_receiver(rd)
          @command_receiver = CommandReceiver.new()
          com_transporter = PlainTransporter.new(@net_multiplexer, @command_receiver, true, 8, false)
          @command_receiver.init(@agent_id, rd, com_transporter)
          @net_multiplexer.add_rudder_state(@command_receiver.rudder, RudderState.new(@command_receiver.rudder, com_transporter))
          BayLog.info("ComRec=%s", @command_receiver)
        end

        def send_accepted_letter(st, client_rd, e, wakeup)
          send_letter(Letter.new(Letter::ACCEPTED, st, client_rd, -1, nil, e), wakeup)
        end

        def send_connected_letter(st, e, wakeup)
          send_letter(Letter.new(Letter::CONNECTED, st, nil, -1, nil, e), wakeup)
        end
        def send_read_letter(st, n, adr, e, wakeup)
          send_letter(Letter.new(Letter::READ, st, nil, n, adr, e), wakeup)
        end

        def send_wrote_letter(st, n, e, wakeup)
          send_letter(Letter.new(Letter::WROTE, st, nil, n, nil, e), wakeup)
        end

        def send_close_req_letter(st, wakeup)
          send_letter(Letter.new(Letter::CLOSEREQ, st, nil, -1, nil, nil), wakeup)
        end

        def shutdown
          BayLog.info("%s shutdown", self)
          if @aborted
            return
          end

          @aborted = true
          BayLog.debug("%s shutdown netMultiplexer", self)
          @net_multiplexer.shutdown()

          GrandAgent.listeners.each do |lis|
            lis.remove(@agent_id)
          end
          @command_receiver.end()
          GrandAgent.agents.delete(@agent_id)

          @agent_id = -1
          if BayServer.harbor.multi_core
            BayLog.debug("%s exit", self)
            exit(1)
          end
        end

        def abort
          BayLog.fatal("%s abort", self)
        end


        def reload_cert
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

        def add_postpone(p)
          @postpone_queue_lock.synchronize do
            @postpone_queue << p
          end
        end

        def count_postpone
          return @postpone_queue.length
        end

        def req_catch_up
          BayLog.debug("%s Req catchUp", self)
          if count_postpone > 0
            catch_up
          else
            begin
              @command_receiver.send_command_to_monitor(self, CMD_CATCHUP, false)
            rescue IOError => e
              BayLog.error_e(e)
              abort
            end
          end
        end

        def catch_up
          BayLog.debug("%s catchUp", self)
          @postpone_queue_lock.synchronize do
            if not @postpone_queue.empty?
              r = @postpone_queue.shift
              r.run()
            end
          end
        end

        #########################################
        # Private methods
        #########################################
        private
        def ring
          BayLog.debug("%s Ring", self)
          # timeout check
          @timer_handlers.each do |h|
            h.on_timer
          end
          @last_timeout_check = Time.now.tv_sec
        end

        def send_letter(let, wakeup)
          @letter_queue_lock.synchronize do
            @letter_queue << let
          end

          if wakeup
            @recipient.wakeup
          end
        end

        def on_accept(let)
          p = BayServer::anchorable_port_map[let.state.rudder]

          begin
            if let.err != nil
              raise let.err
            end

            p.on_connected(@agent_id, let.client_rudder)
          rescue IOError => e
            let.state.transporter.on_error(let.state.rudder, e)
            next_action(let.state, NextSocketAction::CLOSE, false)
          rescue HttpException => e
            BayLog.error_e(e)
            let.client_rudder.close
          end

          if !@net_multiplexer.is_busy
            let.state.multiplexer.next_accept(let.state)
          end
        end

        def on_connect(let)
          st = let.state
          if st.closed
            BayLog.debug("%s Rudder is already closed: rd=%s", self, st.rudder);
            return;
          end

          BayLog.debug("%s connected rd=%s", self, st.rudder)
          next_act = nil
          begin
            if let.err != nil
              raise let.err
            end

            next_act = st.transporter.on_connect(st.rudder)
            BayLog.debug("%s nextAct=%s", self, next_act)
          rescue IOError => e
            st.transporter.on_error(st.rudder, e)
            next_act = NextSocketAction::CLOSE
          end

          if next_act == NextSocketAction::READ
            # Read more
            st.multiplexer.cancel_write(st)
          end

          next_action(st, next_act, false)
        end

        def on_read(let)
          st = let.state
          if st.closed
            BayLog.debug("%s Rudder is already closed: rd=%s", self, st.rudder)
            return
          end

          begin
            if let.err != nil
              BayLog.debug("%s error on OS read %s", self, let.err)
              raise let.err
            end

            BayLog.debug("%s read %d bytes (rd=%s)", self, let.n_bytes, st.rudder)
            st.bytes_read += let.n_bytes

            if let.n_bytes <= 0
              st.read_buf.clear
              next_act = st.transporter.on_read(st.rudder, "", let.address)
            else
              next_act = st.transporter.on_read(st.rudder, st.read_buf, let.address)
            end

          rescue => e
            st.transporter.on_error(st.rudder, e)
            next_act = NextSocketAction::CLOSE
          end

          next_action(st, next_act, true)
        end

        def on_wrote(let)
          st = let.state
          if st.closed
            BayLog.debug("%s Rudder is already closed: rd=%s", self, st.rudder)
            return
          end

          begin
            if let.err != nil
              BayLog.debug("%s error on OS write %s", self, let.err)
              raise let.err
            end

            BayLog.debug("%s wrote %d bytes rd=%s qlen=%d", self, let.n_bytes, st.rudder, st.write_queue.length)
            st.bytes_wrote += let.n_bytes

            if st.write_queue.empty?
              raise Sink("%s Write queue is empty: rd=%s", self, st.rudder)
            end

            unit = st.write_queue[0]
            if unit.buf.length > 0
              BayLog.debug("Could not write enough data buf_len=%d", unit.buf.length)
            else
              st.multiplexer.consume_oldest_unit(st)
            end

            write_more = true

            st.writing_lock.synchronize do
              if st.write_queue.empty?
                write_more = false
                st.writing = false
              end
            end

            if write_more
              st.multiplexer.next_write(st)
            else
              if st.finale
                # close
                BayLog.debug("%s finale return Close", self)
                next_action(st, NextSocketAction::CLOSE, false)
              else
                # Write off
                st.multiplexer.cancel_write(st)
              end
            end
          rescue SystemCallError, IOError => e
            BayLog.debug("%s IO error on wrote", self)
            st.transporter.on_error(st.rudder, e)
            next_action(st, NextSocketAction::CLOSE, false)
          end
        end

        def on_close_req(let)
          st = let.state
          BayLog.debug("%s reqClose rd=%s", self, st.rudder)
          if st.closed
            BayLog.debug("%s Rudder is already closed: rd=%s", self, st.rudder)
            return
          end

          st.multiplexer.close_rudder(st)
          st.access
        end

        def next_action(st, act, reading)
          BayLog.debug("%s next action: %s (reading=%s)", self, act, reading)
          cancel = false

          case(act)
          when NextSocketAction::CONTINUE
            if reading
              st.multiplexer.next_read(st)
            end

          when NextSocketAction::READ
            st.multiplexer.next_read(st)

          when NextSocketAction::WRITE
            if reading
              cancel = true
            end

          when NextSocketAction::CLOSE
            if reading
              cancel = true
            end
            st.multiplexer.close_rudder(st)

          when NextSocketAction::SUSPEND
            if reading
              cancel = true
            end

          else
            raise ArgumentError.new("Invalid action: #{act}")

          end

          if cancel
            st.multiplexer.cancel_read(st)
            st.reading_lock.synchronize do
              BayLog.debug("%s Reading off %s", self, st.rudder)
              st.reading = false
            end
          end

          st.access
        end


        ######################################################
        # class methods
        ######################################################
        def GrandAgent.init(agt_ids, max_ships)
          @agent_count = agt_ids.length
          @max_ships = max_ships

          if BayServer.harbor.multi_core
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
            lis.add(agt.agent_id)
          end

          return agt
        end

        def GrandAgent.add_lifecycle_listener(lis)
          @listeners.append(lis)
        end
      end
    end
  end
end
