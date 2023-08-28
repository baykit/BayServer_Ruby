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
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Util

          class ChannelState
            attr_accessor :accepted
            attr :channel
            attr :listener
            attr_accessor :connecting
            attr_accessor :closing

            attr :last_access_time

            def initialize(ch, lis)
              @channel = ch
              @listener = lis
              @accepted = false
              @connecting = false
              @closing = false
            end

            def access
              @last_access_time = DateTime.now
            end

            def to_s
             if @listener != nil
                str = @listener.to_s
              else
                str = super.to_s
             end
             if @closing
               str += " closing";
             end
             return str
            end
          end

          class ChannelOperation

            attr :ch
            attr_accessor :op
            attr_accessor :to_connect
            attr_accessor :to_close


            def initialize(ch, op, to_connect, to_close)
              @ch = ch
              @op = op
              @to_connect = to_connect
              @to_close = to_close
            end


          end

          attr :agent
          attr :ch_map
          attr :ch_count
          attr :operations
          attr :operations_lock

          def initialize(ship_agent)
            @agent = ship_agent
            @ch_map = {}
            @ch_count = 0
            @operations = []
            @operations_lock = Monitor.new()
          end


          def to_s()
            return @agent.to_s()
          end

          def handle_channel(ch, op)

            ch_state = find_channel_state(ch)
            if ch_state == nil
              BayLog.error("Cannot find fd state (Maybe file is closed)")
              @agent.selector.unregister(ch)
              return
            end

            next_action = nil
            begin

              if ch_state.closing
                next_action = NextSocketAction::CLOSE

              elsif ch_state.connecting
                ch_state.connecting = false
                # connectable
                next_action = ch_state.listener.on_connectable(ch)
                if next_action == nil
                  raise Sink.new("unknown next action")
                elsif next_action == NextSocketAction::CONTINUE
                  ask_to_read(ch)
                end

              else
                if op & Selector::OP_READ != 0
                  # readable
                  next_action = ch_state.listener.on_readable(ch)
                  if next_action == nil
                    raise Sink.new("unknown next action")
                  elsif next_action == NextSocketAction::WRITE
                    op = @agent.selector.get_op(ch)
                    op = op | Selector::OP_WRITE
                    @agent.selector.modify(ch, op)
                  end
                end

                if (next_action != NextSocketAction::CLOSE) && (op & Selector::OP_WRITE != 0)
                  # writable
                  next_action = ch_state.listener.on_writable(ch)
                  if next_action == nil
                    raise Sink.new("unknown next action")
                  elsif next_action == NextSocketAction::READ
                    # Handle as "Write Off"
                    op = @agent.selector.get_op(ch)
                    op = op & ~Selector::OP_WRITE
                    if op == 0
                      @agent.selector.unregister(ch)
                    else
                      @agent.selector.modify(ch, op)
                    end
                  end
                end
              end


              if next_action == nil
                raise Sink.new("unknown next action")
              end

            rescue Sink => e
              raise e

            rescue => e
              if e.kind_of? EOFError
                BayLog.debug("%s Socket closed by peer: skt=%s", @agent, ch.inspect)
              elsif e.kind_of? SystemCallError
                BayLog.debug("%s O/S error: %s (skt=%s)", @agent, e.message, ch.inspect)
              elsif e.kind_of? IOError
                BayLog.debug("%s IO error: %s (skt=%s)", @agent, e.message, ch.inspect)
              elsif e.kind_of? OpenSSL::SSL::SSLError
                BayLog.debug("%s SSL error: %s (skt=%s)", @agent, e.message, ch.inspect)
              else
                BayLog.error("%s Unhandled error error: %s (skt=%s)", @agent, e, ch.inspect)
                throw e
              end
              # Cannot handle Exception any more
              ch_state.listener.on_error(ch, e)
              next_action = NextSocketAction::CLOSE
            end

            cancel = false
            ch_state.access()
            BayLog.trace("%s next=%d", ch_state, next_action)
            case next_action
            when NextSocketAction::CLOSE
              close_channel(ch, ch_state)
              cancel = false   # already canceled in close_channel method

            when NextSocketAction::SUSPEND
              cancel = true

            when NextSocketAction::CONTINUE, NextSocketAction::READ, NextSocketAction::WRITE
              # do nothing

            else
              raise RuntimeError.new("IllegalState:: #{next_action}")
            end

            if cancel
              BayLog.trace("%s cancel key chState=%s", @agent, ch_state)
              @agent.selector.unregister(ch)
            end
          end

          def register_channel_ops()
            if @operations.empty?
              return 0
            end

            @operations_lock.synchronize do
              nch = @operations.length
              @operations.each do |ch_op|
                st = self.find_channel_state(ch_op.ch)
                if ch_op.ch.closed?
                  # Channel is closed before register operation
                  BayLog.debug("%s Try to register closed socket (Ignore)", @agent)
                  next
                end

                begin
                  BayLog.trace("%s register op=%s chState=%s", @agent, self.class.op_mode(ch_op.op), st)
                  op = @agent.selector.get_op(ch_op.ch)
                  if op == nil
                    @agent.selector.register(ch_op.ch, ch_op.op)
                  else
                    new_op = op | ch_op.op
                    BayLog.debug("%s Already registered ch=%s op=%s update to %s", @agent, ch_op.ch, self.class.op_mode(op), self.class.op_mode(new_op))
                    @agent.selector.modify(ch_op.ch, new_op)
                  end

                  if ch_op.to_connect
                    if st == nil
                      BayLog.warn("%s register connect but ChannelState is null", @agent);
                    else
                      st.connecting = true
                    end

                  elsif ch_op.to_close
                    if st == nil
                      BayLog.warn("%s chState=%s register close but ChannelState", self.agent);
                    else
                      st.closing = true
                    end
                  end

                rescue => e
                  cst = find_channel_state(ch_op.ch)
                  BayLog.error_e(e, "%s Cannot register operation: %s", self.agent, cst != nil ? cst.listener : nil)
                end
              end

              @operations.clear()
              return nch

            end
          end

          def close_timeout_sockets()
            if @ch_map.empty?
              return
            end

            close_list = []
            now = DateTime.now
            @ch_map.values.each do |ch_state|
              if ch_state.listener != nil
                duration =  ((now - ch_state.last_access_time) * 86400).to_i
                if ch_state.listener.check_timeout(ch_state.channel, duration)
                  BayLog.debug("%s timeout: skt=%s", @agent, ch_state.channel)
                  close_list << ch_state
                end
              end
            end

            close_list.each do |ch_state|
              close_channel ch_state.channel, ch_state
            end
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
            ch_state = find_channel_state(ch)
            BayLog.debug("%s askToConnect addr=%s skt=%s chState=%s", @agent, addr, ch, ch_state)

            begin
              ch.connect_nonblock(addr)
            rescue IO::WaitWritable => e
              #BayLog.error_e(e)
            end

            ch_state.connecting = true
            add_operation(ch, Selector::OP_READ, true)
          end

          def ask_to_read(ch)
            ch_state = find_channel_state(ch)
            BayLog.debug("%s askToRead chState=%s", @agent, ch_state);

            if ch.closed?
              raise IOError.new("Channel is closed")
            end

            add_operation(ch, Selector::OP_READ)

            if ch_state != nil
              ch_state.access()
            end
          end

          def ask_to_write(ch)
            ch_state = find_channel_state(ch)
            BayLog.debug("%s askToWrite chState=%s", @agent, ch_state);

            if ch.closed?
              BayLog.warn("%s Channel is closed: %s", @agent, ch)
              return
            end

            add_operation(ch, Selector::OP_WRITE)

            if ch_state == nil
              BayLog.error("Unknown socket (or closed)")
              return
            end

            ch_state.access()
          end

          def ask_to_close(ch)
            ch_state = find_channel_state(ch)
            BayLog.debug("%s askToClose chState=%s", @agent, ch_state);

            if ch_state == nil
              BayLog.warn("%s channel state not found: %s", @agent, ch)
              return
            end

            ch_state.closing = true
            add_operation(ch, Selector::OP_WRITE, false, true)

            ch_state.access
          end


          private

          def add_operation(ch, op, to_connect=false, to_close=false)
            @operations_lock.synchronize do
              found = false
              @operations.each do |ch_op|
                if ch_op.ch == ch
                  ch_op.op |= op
                  ch_op.to_close = (ch_op.to_close or to_close)
                  ch_op.to_connect = (ch_op.to_connect or to_connect)
                  found = true
                  BayLog.trace("%s Update operation: %s con=%s close=%s ch=%s", @agent, self.class.op_mode(ch_op.op), ch_op.to_connect, ch_op.to_close, ch_op.ch.inspect())
                end
              end

              if not found
                BayLog.trace("%s New operation: %s con=%s close=%s ch=%s", @agent, self.class.op_mode(op), to_connect, to_close, ch.inspect());
                @operations << ChannelOperation.new(ch, op, to_connect, to_close)
              end
            end

            @agent.wakeup
          end

          def close_channel(ch, ch_state)
            BayLog.debug("%s Close chState=%s", @agent, ch_state)

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

            ch.close()
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
            mode_str = ""
            if (mode & Selector::OP_READ) != 0
              mode_str = "OP_READ"
            end

            if (mode & Selector::OP_WRITE) != 0
              if mode_str != ""
                mode_str += "|"
              end
              mode_str += "OP_WRITE"
            end

            return mode_str
          end
        end
    end
  end
end
