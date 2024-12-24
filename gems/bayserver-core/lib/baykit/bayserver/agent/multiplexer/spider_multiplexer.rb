require 'baykit/bayserver/common/recipient'
require 'baykit/bayserver/rudders/rudder'
require 'baykit/bayserver/rudders/io_rudder'

require 'baykit/bayserver/agent/multiplexer/multiplexer_base'
require 'baykit/bayserver/agent/multiplexer/write_unit'
require 'baykit/bayserver/agent/timer_handler'

module Baykit
  module BayServer
    module Agent
      module Multiplexer
        class SpiderMultiplexer < Baykit::BayServer::Agent::Multiplexer::MultiplexerBase
          include Baykit::BayServer::Agent::TimerHandler #implements
          include Baykit::BayServer::Common::Recipient  # implements
          include Baykit::BayServer::Agent::Multiplexer

          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Util

          class ChannelOperation

            attr :rudder
            attr_accessor :op
            attr_accessor :to_connect


            def initialize(rd, op, to_connect)
              @rudder = rd
              @op = op
              @to_connect = to_connect
            end
          end

          attr :anchorable
          attr :selector
          attr :operations
          attr :operations_lock
          attr :select_wakeup_pipe
          attr :handshaked

          def initialize(agt, anchorable)
            super(agt)
            @anchorable = anchorable
            @operations = []
            @operations_lock = Mutex.new
            @selector = Selector.new
            @select_wakeup_pipe = IO.pipe
            @selector.register(@select_wakeup_pipe[0], Selector::OP_READ)

            @agent.add_timer_handler(self)
            @handshaked = false
          end
          def to_s
            return "SpdMpx[" + @agent.to_s + "]"
          end


          #########################################
          # Implements Multiplexer
          #########################################

          def req_accept(rd)
            st = get_rudder_state(rd)
            selector.register(rd.io, Selector::OP_READ)
            st.accepting = true
          end

          def req_connect(rd, adr)
            st = get_rudder_state(rd)
            BayLog.debug("%s reqConnect adr=%s rd=%s chState=%s", @agent, adr.canonname, rd, st)

            rd.set_non_blocking

            begin
              rd.io.connect(adr)
            rescue IO::WaitWritable => e
              #BayLog.error_e(e)
            end

            st.connecting = true
            add_operation(rd, Selector::OP_WRITE, true)
          end

          def req_read(rd)
            st = get_rudder_state(rd)
            BayLog.debug("%s reqRead st=%s", @agent, st);

            add_operation(rd, Selector::OP_READ)

            if st != nil
              st.access
            end
          end

          def req_write(rd, buf,adr, tag, &lis)
            st = get_rudder_state(rd)
            BayLog.debug("%s req write st=%s tag=%s", @agent, st, tag)

            if st == nil || st.closed
              BayLog.warn("%s Channel is closed: %s", @agent, rd)
              lis.call()
              return
            end

            unt = WriteUnit.new(buf, adr, tag, &lis)
            st.write_queue_lock.synchronize do
              st.write_queue << unt
            end

            add_operation(rd, Selector::OP_WRITE)

            st.access
          end

          def req_end(rd)
            st = get_rudder_state(rd)
            if st == nil
              return
            end

            st.end
            st.access
          end

          def req_close(rd)
            st = get_rudder_state(rd)
            BayLog.debug("%s reqClose rd=%s", @agent, rd);

            if st == nil
              BayLog.warn("%s channel state not found: %s", @agent, rd)
              return
            end

            close_rudder(st)
            @agent.send_closed_letter(st, false)

            st.access
          end


          def shutdown
            wakeup
          end

          def is_non_blocking
            return true
          end

          def use_async_api
            return false
          end


          def cancel_read(st)
            @selector.unregister(st.rudder.io)
          end

          def cancel_write(st)
            op = @selector.get_op(st.rudder.io) & ~Selector::OP_WRITE
            # Write OP off
            if op != Selector::OP_READ
              @selector.unregister(st.rudder.io)
            else
              @selector.modify(st.rudder.io, op)
            end
          end

          def next_accept(st)
          end

          def next_read(st)
          end

          def next_write(st)
          end

          def close_rudder(st)
            @selector.unregister(st.rudder.io)
            super
          end


          def on_busy
            BayLog.debug("%s onBusy", agent)
            BayServer::anchorable_port_map.keys.each do |rd|
              @selector.unregister(rd.io)
              st = get_rudder_state(rd)
              st.accepting = false
            end
          end

          def on_free
            BayLog.debug("%s onFree aborted=%s", agent, agent.aborted);
            if agent.aborted
              return
            end

            BayServer.anchorable_port_map.keys.each do |rd|
              req_accept(rd)
            end
          end

          #########################################
          # Implements TimerHandler
          #########################################

          def on_timer
            close_timeout_sockets
          end
          #########################################
          # Implements Recipient
          #########################################

          #
          # Receive letters
          #
          def receive(wait)
            if not wait
              selected_map = @selector.select()
            else
              selected_map = @selector.select(GrandAgent::SELECT_TIMEOUT_SEC)
            end
            #BayLog.debug("%s selected: %s", self, selected_map)

            register_channel_ops

            selected_map.keys.each do |io|
              if io == @select_wakeup_pipe[0]
                # Waked up by req_*
                on_waked_up
              else
                handle_channel(io, selected_map[io])
              end
            end

            return !selected_map.empty?
          end

          #
          # Wake up the recipient
          #
          def wakeup
            IOUtil.write_int32(@select_wakeup_pipe[1], 0)
          end

          private
          def add_operation(rd, op, to_connect=false)
            @operations_lock.synchronize do
              found = false
              @operations.each do |ch_op|
                if ch_op.rudder == rd
                  ch_op.op |= op
                  ch_op.to_connect = (ch_op.to_connect or to_connect)
                  found = true
                  BayLog.trace("%s Update operation: %s con=%s ch=%s",
                               @agent, self.class.op_mode(ch_op.op), ch_op.to_connect, ch_op.rudder.inspect())
                end
              end

              if not found
                BayLog.trace("%s New operation: %d con=%s close=%s ch=%s", @agent, op, to_connect, rd.inspect)
                @operations << ChannelOperation.new(rd, op, to_connect)
              end
            end

            wakeup
          end

          def register_channel_ops
            if @operations.empty?
              return 0
            end

            @operations_lock.synchronize do
              nch = @operations.length
              @operations.each do |rd_op|
                st = get_rudder_state(rd_op.rudder)
                if rd_op.rudder.io.closed?
                  # Channel is closed before register operation
                  BayLog.debug("%s Try to register closed socket (Ignore)", @agent)
                  next
                end

                begin
                  io = rd_op.rudder.io
                  BayLog.trace("%s register op=%s st=%s", @agent, self.class.op_mode(rd_op.op), st)
                  op = @selector.get_op(io)
                  if op == nil
                    @selector.register(io, rd_op.op)
                  else
                    new_op = op | rd_op.op
                    BayLog.trace("%s Already registered rd=%s op=%s update to %s", @agent, rd_op.rudder, self.class.op_mode(op), self.class.op_mode(new_op))
                    @selector.modify(io, new_op)
                  end

                  if rd_op.to_connect
                    if st == nil
                      BayLog.warn("%s register connect but ChannelState is null", @agent);
                    else
                      st.connecting = true
                    end

                  end

                rescue => e
                  st = get_rudder_state(rd_op.rudder)
                  BayLog.error_e(e, "%s Cannot register operation: %s", self.agent, st.rudder)
                end
              end

              @operations.clear
              return nch
            end
          end

          def handle_channel(io, op)

            #BayLog.info("%s handle_channel io=%s op=%d", self, io, op)
            st = find_rudder_state_by_key(io)
            if st == nil
              BayLog.debug("Cannot find fd state (Maybe file is closed)")
              @selector.unregister(io)
              return
            end

            begin

              if st.connecting
                on_connectable(st)

                st.connecting = false
                # "Write-OP Off"
                op = @selector.get_op(io)
                op = op & ~Selector::OP_WRITE
                if op == 0
                  @selector.unregister(io)
                else
                  @selector.modify(io, op)
                end

              elsif st.accepting
                on_acceptable(st)

              else
                if op & Selector::OP_READ != 0
                  # readable
                  on_readable(st)
=begin
                  next_action = st.listener.on_readable(rd)
                  if next_action == nil
                    raise Sink.new("unknown next action")
                  elsif next_action == NextSocketAction::WRITE
                    op = @agent.selector.get_op(rd)
                    op = op | Selector::OP_WRITE
                    @agent.selector.modify(rd, op)
                  end
=end
                end

                if op & Selector::OP_WRITE != 0
                  # writable
                  on_writable(st)
=begin
                  next_action = st.listener.on_writable(rd)
                  if next_action == nil
                    raise Sink.new("unknown next action")
                  elsif next_action == NextSocketAction::READ
                    # Handle as "Write Off"
                    op = @agent.selector.get_op(rd)
                    op = op & ~Selector::OP_WRITE
                    if op == 0
                      @agent.selector.unregister(rd)
                    else
                      @agent.selector.modify(rd, op)
                    end
                  end
=end
                end
              end

            rescue Sink => e
              raise e

            rescue => e
              if e.kind_of? EOFError
                BayLog.debug("%s Socket closed by peer: skt=%s", @agent, st.rudder.inspect)
              elsif e.kind_of? SystemCallError
                BayLog.debug("%s O/S error: %s (skt=%s)", @agent, e.message, st.rudder.inspect)
              elsif e.kind_of? IOError
                BayLog.debug("%s IO error: %s (skt=%s)", @agent, e.message, st.rudder.inspect)
              elsif e.kind_of? OpenSSL::SSL::SSLError
                BayLog.debug_e(e, "%s SSL error: %s (skt=%s)", @agent, e.message, st.rudder.inspect)
              else
                BayLog.error_e(e, "%s Unhandled error error: (skt=%s)",  @agent, st.rudder.inspect)
                raise e
              end
              # Cannot handle Exception any more
              BayLog.error_e(e)
              @agent.send_error_letter(st, e, false)
            end

            st.access()
          end

          def on_acceptable(st)

            begin
              client_skt, = st.rudder.io.accept_nonblock
            rescue IO::WaitReadable
              # Maybe another agent get socket
              BayLog.debug("Accept failed (must wait readable)")
              return
            end

            BayLog.debug("%s Accepted: server=%s(%d) client=%s(%d)", self, st.rudder.io, st.rudder.io.fileno, client_skt, client_skt.fileno)
            client_rd = IORudder.new(client_skt)
            client_rd.set_non_blocking
            #client_skt.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)

            @agent.send_accepted_letter(st, client_rd, false)

          end

          def on_connectable(st)
            BayLog.trace("%s onConnectable", self)

            # check connected
            begin
              buf = ""
              st.rudder.io.syswrite(buf)
            rescue => e
              BayLog.error("Connect failed: %s", e)
              @agent.send_error_letter(st, e, false)
              return
            end

            @agent.send_connected_letter(st, false)
          end

          def on_readable(st)
            # Read data

            BayLog.trace("%s on_readable", self)

            begin
              if st.handshaking
                begin
                  # Calls accept API for client socket
                  st.rudder.io.accept_nonblock
                  st.handshaking = false

                  BayLog.debug("%s Handshake done (rd=%s)", self, st.rudder)
                  app_protocols = st.rudder.io.context.alpn_protocols

                  # HELP ME
                  #   This code does not work!
                  #   We cannot get application protocol name
                  proto = nil
                  if app_protocols != nil && app_protocols.length > 0
                    proto = app_protocols[0]
                  end

                rescue IO::WaitReadable => e
                  BayLog.debug("%s Handshake status: read more st=%s", self, st)
                  return NextSocketAction::CONTINUE
                rescue IO::WaitWritable => e
                  BayLog.debug("%s Handshake status: write more st=%s", self, st)
                  req_write(st.rudder, "", nil, nil)
                  return NextSocketAction::CONTINUE
                end
              end

              begin
                len = st.rudder.read(st.read_buf, st.buf_size)
              rescue IO::WaitReadable => e
                BayLog.debug("%s Read status: read more", self)
                return NextSocketAction::CONTINUE
              rescue IO::WaitWritable => e
                BayLog.debug("%s Read status: write more", self)
                @channel_handler.ask_to_write(@ch)
                return NextSocketAction::CONTINUE
              rescue EOFError => e
                BayLog.debug("%s EOF", self)
                len = 0
              end

              BayLog.debug("%s read %d bytes", self, len)
              @agent.send_read_letter(st, len, nil, false)

            rescue Exception => e
              BayLog.debug_e(e, "%s Unhandled error", self)
              @agent.send_error_letter(st, e, false)
              return
            end
          end

          def on_writable(st)
            begin
              if st.write_queue.empty?
                raise IOError.new(@agent.to_s + " No data to write: " + st.rudder.to_s)
              end

              wunit = st.write_queue[0]

              BayLog.debug("%s Try to write: rd=%s pkt=%s len=%d closed=%s adr=%s",
                           self, st.rudder, wunit.tag, wunit.buf.length, st.closed, wunit.adr);
              #BayLog.debug(this + " " + new String(wUnit.buf.array(), 0, wUnit.buf.limit()));

              n = st.rudder.write(wunit.buf)
              #BayLog.debug("%s Wrote: rd=%s len=%d",self, st.rudder, n);
              wunit.buf.slice!(0, n)
              @agent.send_wrote_letter(st, n, false)

            rescue SystemCallError, IOError => e
              BayLog.debug_e(e, "%s IO error", self)
              @agent.send_error_letter(st, e, false)
            end
          end

          def on_waked_up
            #BayLog.debug("%s waked up", self)
            val = IOUtil.read_int32(@select_wakeup_pipe[0])
          end

          def self.op_mode(mode)
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
end