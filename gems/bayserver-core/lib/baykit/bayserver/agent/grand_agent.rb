require 'socket'
require 'objspace'

require 'baykit/bayserver/sink'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/rudders/udp_rudder'
require 'baykit/bayserver/agent/command_receiver'
require 'baykit/bayserver/agent/letters/package'
require 'baykit/bayserver/agent/multiplexer/spider_multiplexer'
require 'baykit/bayserver/agent/multiplexer/spin_multiplexer'
require 'baykit/bayserver/agent/multiplexer/job_multiplexer'
require 'baykit/bayserver/agent/multiplexer/taxi_multiplexer'
require 'baykit/bayserver/agent/monitor/grand_agent_monitor'
require 'baykit/bayserver/agent/signal/signal_agent'

require 'baykit/bayserver/common/rudder_state'
require 'baykit/bayserver/docker/harbor'
require 'baykit/bayserver/util/object_store'

require 'baykit/bayserver/train/train_runner'
require 'baykit/bayserver/taxi/taxi_runner'

require 'baykit/bayserver/util/io_util'
require 'baykit/bayserver/util/rough_time'
require 'baykit/bayserver/util/selector'

module Baykit
  module BayServer
    module Agent
      class GrandAgent
        include Baykit::BayServer
        include Baykit::BayServer::Train
        include Baykit::BayServer::Taxi
        include Baykit::BayServer::Agent::Signal
        include Baykit::BayServer::Agent::Letters
        include Baykit::BayServer::Agent::Multiplexer
        include Baykit::BayServer::Docker
        include Baykit::BayServer::Util
        include Baykit::BayServer::Common
        include Baykit::BayServer::Protocol

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
        attr :taxi_multiplexer
        attr :file_multiplexer
        attr :recipient

        attr :max_inbound_ships
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

          # Per-agent ObjectStore pools for Letter subclasses. Each
          # send_xxx_letter rents from the appropriate store + init()s
          # the fields; the receive() loop Returns each letter via
          # return_letter() after consuming it. Letter#reset clears
          # the rudder/multiplexer back-refs so the previous request's
          # state can be GC'd while the shells stay cached.
          @accepted_letter_store  = Baykit::BayServer::Util::ObjectStore.new(lambda { Letters::AcceptedLetter.new })
          @connected_letter_store = Baykit::BayServer::Util::ObjectStore.new(lambda { Letters::ConnectedLetter.new })
          @read_letter_store      = Baykit::BayServer::Util::ObjectStore.new(lambda { Letters::ReadLetter.new })
          @wrote_letter_store     = Baykit::BayServer::Util::ObjectStore.new(lambda { Letters::WroteLetter.new })
          @closed_letter_store    = Baykit::BayServer::Util::ObjectStore.new(lambda { Letters::ClosedLetter.new })
          @error_letter_store     = Baykit::BayServer::Util::ObjectStore.new(lambda { Letters::ErrorLetter.new })

          @spider_multiplexer = SpiderMultiplexer.new(self, anchorable)
          @spin_multiplexer = SpinMultiplexer.new(self)
          @job_multiplexer = JobMultiplexer.new(self, anchorable)
          @taxi_multiplexer = TaxiMultiplexer.new(self)

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

          case BayServer.harbor.file_multiplexer
          when Harbor::MULTIPLEXER_TYPE_SPIDER
            @file_multiplexer = @spider_multiplexer
          when Harbor::MULTIPLEXER_TYPE_SPIN
            @file_multiplexer = @spin_multiplexer
          when Harbor::MULTIPLEXER_TYPE_JOB
            @file_multiplexer = @job_multiplexer
          when Harbor::MULTIPLEXER_TYPE_TAXI
            @file_multiplexer = @taxi_multiplexer
          else
            raise Sink.new("Multiplexer not supported: %s", Harbor.get_multiplexer_type_name(BayServer.harbor.file_multiplexer))
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
            @command_receiver.rudder.set_non_blocking
          end

          @net_multiplexer.req_read(@command_receiver.rudder)

          if @anchorable
            # Adds server socket channel of anchorable ports
            BayServer.anchorable_port_map.keys.each do |rd|
              if @net_multiplexer.is_non_blocking
                rd.set_non_blocking
              end
              st = RudderStateStore.get_store(@agent_id).rent
              st.init(rd)
              @net_multiplexer.add_rudder_state(rd, st)
            end
          end

          # Set up unanchorable (UDP) channels
          BayServer.unanchorable_port_map.each do |io_rd, port_dkr|
            # Wrap the UDP socket in UdpRudder for sender-address support
            udp_rd = Baykit::BayServer::Rudders::UdpRudder.new(io_rd.io)
            if @net_multiplexer.is_non_blocking
              udp_rd.set_non_blocking
            end
            tp = port_dkr.new_transporter(@agent_id, udp_rd)
            st = RudderStateStore.get_store(@agent_id).rent
            st.init(udp_rd, tp)
            @net_multiplexer.add_rudder_state(udp_rd, st)
            @net_multiplexer.req_read(udp_rd)
          end


          @net_multiplexer.on_free
          begin
            while true

              if not @spin_multiplexer.is_empty
                # If "SpinHandler" is running, the select function does not block.
                received = @recipient.receive(false)
                @spin_multiplexer.process_data
              else
                received = @recipient.receive(true)
              end

              if @aborted
                BayLog.info("%s aborted by another thread", self)
                break
              end

              if @spin_multiplexer.is_empty && @letter_queue.empty?
                # timed out
                # check per 10 seconds
                if Baykit::BayServer::Util::RoughTime.current_time_secs - @last_timeout_check >= 10
                  ring
                end
              end

              while !@letter_queue.empty?
                let = nil
                @letter_queue_lock.synchronize do
                  let = @letter_queue.shift
                end

                begin
                  st = let.multiplexer.get_rudder_state(let.rudder)
                  if st == nil
                    BayLog.debug("%s rudder is already returned: %s", self, let.rudder)
                    next
                  end

                  case let
                  when AcceptedLetter
                    on_accepted(let, st)
                  when ConnectedLetter
                    on_connected(let, st)
                  when ReadLetter
                    on_read(let, st)
                  when WroteLetter
                    on_wrote(let, st)
                  when ClosedLetter
                    on_closed(let, st)
                  when ErrorLetter
                    on_error(let, st)
                  end
                ensure
                  return_letter(let)
                end
              end
            end # while

          rescue Exception => e
            BayLog.fatal_e(e, "Uncaught Error: %s", e)
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

          st = RudderStateStore.get_store(@agent_id).rent
          st.init(@command_receiver.rudder, com_transporter)
          @net_multiplexer.add_rudder_state(@command_receiver.rudder, st)
        end

        def send_accepted_letter(rd, mpx, client_rd, wakeup)
          if rd == nil
            raise ArgumentError.new
          end
          let = @accepted_letter_store.rent
          let.init(rd, mpx, client_rd)
          send_letter(let, wakeup)
        end

        def send_connected_letter(rd, mpx, wakeup)
          if rd == nil
            raise ArgumentError.new
          end
          let = @connected_letter_store.rent
          let.init(rd, mpx)
          send_letter(let, wakeup)
        end

        def send_read_letter(rd, mpx, n, adr, wakeup)
          if rd == nil
            raise ArgumentError.new
          end
          let = @read_letter_store.rent
          let.init(rd, mpx, n, adr)
          send_letter(let, wakeup)
        end

        def send_wrote_letter(rd, mpx, n, wakeup)
          if rd == nil
            raise ArgumentError.new
          end
          let = @wrote_letter_store.rent
          let.init(rd, mpx, n)
          send_letter(let, wakeup)
        end

        def send_closed_letter(rd, mpx, wakeup)
          if rd == nil
            raise ArgumentError.new
          end
          let = @closed_letter_store.rent
          let.init(rd, mpx)
          send_letter(let, wakeup)
        end

        def send_error_letter(rd, mpx, err, wakeup)
          if rd == nil
            raise ArgumentError.new
          end
          let = @error_letter_store.rent
          let.init(rd, mpx, err)
          send_letter(let, wakeup)
        end

        # Return a consumed letter to its appropriate ObjectStore.
        def return_letter(let)
          case let
          when Letters::AcceptedLetter  then @accepted_letter_store.Return(let)
          when Letters::ConnectedLetter then @connected_letter_store.Return(let)
          when Letters::ReadLetter      then @read_letter_store.Return(let)
          when Letters::WroteLetter     then @wrote_letter_store.Return(let)
          when Letters::ClosedLetter    then @closed_letter_store.Return(let)
          when Letters::ErrorLetter     then @error_letter_store.Return(let)
          end
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

          if BayServer.harbor.multi_core
            BayLog.debug("%s exit", self)
            exit(1)
          end
          @agent_id = -1
        end

        def abort
          BayLog.fatal("%s abort", self)
        end


        def reload_cert
          BayServer.anchorable_port_map.values().each do |port|
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
          BayLog.trace("%s Ring", self)
          # timeout check
          @timer_handlers.each do |h|
            h.on_timer
          end
          @last_timeout_check = Baykit::BayServer::Util::RoughTime.current_time_secs
        end

        def send_letter(let, wakeup)
          @letter_queue_lock.synchronize do
            @letter_queue << let
          end

          if wakeup
            @recipient.wakeup
          end
        end

        def on_accepted(let, st)
          begin
            p = BayServer::anchorable_port_map[st.rudder]
            p.on_connected(@agent_id, let.client_rudder)
          rescue HttpException => e
            st.transporter.on_error(st.rudder, e)
            next_action(st, NextSocketAction::CLOSE, false)
          end

          if @net_multiplexer.is_busy
            BayLog.warn("%s net multiplexer is busy: %s", self, @net_multiplexer)
            @net_multiplexer.on_busy
            @busy = true
          else
            st.multiplexer.next_accept(st)
          end
        end

        def on_connected(let, st)
          BayLog.debug("%s connected rd=%s", self, st.rudder)
          next_act = nil
          begin
            next_act = st.transporter.on_connected(st.rudder)
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

        def on_read(let, st)
          begin
            BayLog.debug("%s read %d bytes (rd=%s)", self, let.n_bytes, st.rudder)
            st.bytes_read += let.n_bytes

            if let.n_bytes <= 0
              st.read_buf.clear
              next_act = st.transporter.on_read(st.rudder, "", let.address)
            else
              next_act = st.transporter.on_read(st.rudder, st.read_buf, let.address)
            end

          rescue ProtocolException => e
            close = st.transporter.ship.notify_protocol_error(e)
            if !close && st.transporter.server_mode
              next_act = NextSocketAction::CONTINUE
            else
              next_act = NextSocketAction::CLOSE
            end
          rescue IOError => e
            st.transporter.on_error(st.rudder, e)
            next_act = NextSocketAction::CLOSE
          end

          next_action(st, next_act, true)
        end

        def on_wrote(let, st)
          BayLog.debug("%s wrote %d bytes rd=%s qlen=%d", self, let.n_bytes, st.rudder, st.write_queue.length)
          st.bytes_wrote += let.n_bytes

          if st.write_queue.empty?
            # Spurious wrote_letter (e.g. one queued by an earlier
            # on_writable whose bytes have already been accounted for
            # by a peer wrote_letter). Drop instead of raising; the
            # write path is otherwise consistent.
            BayLog.debug("%s wrote letter for empty queue: rd=%s", self, st.rudder)
            return
          end

          write_more = false
          unit = st.write_queue[0]
          if unit.remaining > 0
            BayLog.debug("Could not write enough data remaining=%d", unit.remaining)
            write_more = true
          else
            # Removes write unit from writeQueue
            st.multiplexer.consume_oldest_unit(st)

            st.writing_lock.synchronize do
              if st.write_queue.empty?
                write_more = false
                st.writing = false
              else
                write_more = true
              end
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
        end

        def on_closed(let, st)
          st.multiplexer.remove_rudder_state(st.rudder)

          while st.multiplexer.consume_oldest_unit(st) do

          end

          if st.transporter != nil
            st.transporter.on_closed(st.rudder)
          end

          RudderStateStore.get_store(@agent_id).Return(st)

          if @busy && !@net_multiplexer.is_busy
            BayLog.warn("%s net multiplexer is free: %s", self, @net_multiplexer)
            @net_multiplexer.on_free
            @busy = false
          end
        end

        def on_error(let, st)

          if let.err.is_a?(SystemCallError) ||
            let.err.is_a?(IOError) ||
            let.err.is_a?(OpenSSL::SSL::SSLError) ||
            let.err.is_a?(HttpException)

            if st.transporter != nil
              st.transporter.on_error(st.rudder, let.err)
            else
              BayLog.error_e(let.err, "%s onError error=%s", self, let.err);
            end
            next_action(st, NextSocketAction::CLOSE, false)
          else
            BayLog.fatal_e(let.e, "Cannot handle error")
            raise let.e
          end
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
            st.multiplexer.req_close(st.rudder)

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

        def count_postpone
          return @postpone_queue.length
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
