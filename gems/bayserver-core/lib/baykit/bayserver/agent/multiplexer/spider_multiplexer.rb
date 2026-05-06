require 'baykit/bayserver/common/recipient'
require 'baykit/bayserver/common/write_unit'
require 'baykit/bayserver/rudders/rudder'

require 'baykit/bayserver/rudders/io_rudder'

require 'baykit/bayserver/agent/multiplexer/multiplexer_base'
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
          include Baykit::BayServer::Common

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
            @operations = {}
            @operations_lock = Mutex.new
            # States queued by req_write for an inline-write attempt at the
            # end of receive(). Lets us skip the epoll_ctl(ADD) +
            # selector wait + epoll_ctl(DEL) round-trip for ready sockets.
            @try_write_list = []
            @try_write_lock = Mutex.new

            begin
              require "nio4r"  # gem: nio4r
              require 'baykit/bayserver/util/nio_selector'
              @selector = NioSelector.new
            rescue LoadError => e
              BayLog.debug_e(e, "nio4r gem is not installed. Use Selector instead.")
              require 'baykit/bayserver/util/rb_selector'
              @selector = RbSelector.new
            end


            @select_wakeup_pipe = IO.pipe
            @selector.register(@select_wakeup_pipe[0], Selector::OP_READ)

            @agent.add_timer_handler(self)
            @handshaked = false

            # Per-multiplexer scratch buffer reused by on_writable when
            # gathering more than one WriteUnit into a single
            # write_nonblock call. Pre-allocates the underlying String
            # capacity once; #clear preserves it, and #<< appends in
            # place without allocating. Avoids the per-call
            # `batch.map(&:buf).join` (one Array + one String per call).
            @gather_buf = String.new(capacity: 65536)
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
              rd.io.connect_nonblock(adr)
            rescue IO::WaitWritable => e
              # In non-blocking mode, connect_nonblock raises IO::WaitWritable by design
              # to signal an in-progress connection (this is expected and not an error).
            rescue Errno::EISCONN
              # Connection has been successfully established
            rescue SystemCallError => e
              @agent.send_error_letter(rd, self, e, false)
              return
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

          def req_write(rd, buf, adr, tag, flush, &lis)
            st = get_rudder_state(rd)
            BayLog.debug("%s reqWrite st=%s tag=%s flush=%s", @agent, st, tag, flush)

            if st == nil
              BayLog.warn("%s Channel is closed: %s", @agent, rd)
              lis.call(true)
              return true
            end

            unt = WriteUnit.new(buf, adr, tag, &lis)
            st.write_queue << unt

            # Defer the epoll OP_WRITE registration unless the caller
            # explicitly asked to flush, or the queued bytes have grown
            # past the per-connection buffer size. e491d8f's intermediate
            # sends pass flush=false so headers + small bodies coalesce
            # into a single write.
            #
            # Instead of registering OP_WRITE with epoll and waiting for
            # the next select() to discover that the socket is writable,
            # queue the state on @try_write_list and have receive() try
            # the write inline at the end of its processing. This skips
            # the epoll_ctl(ADD) + epoll_ctl(DEL) pair on the common
            # case where the kernel send buffer has room. Partial writes
            # fall back to the OP_WRITE path naturally because
            # on_writable re-queues unfinished work.
            flush_threshold = [st.buf_size, BayServer.harbor.ship_buffer_size].min
            if st.remaining > 0 && (flush || st.remaining >= flush_threshold)
              @try_write_list << st
              wakeup
            end

            st.access
            return st.buffer_available?
          end

          def req_transfer(rd, file_rd, ofs, len, &lis)
            raise Sink.new
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

            close_rudder(rd)
            @agent.send_closed_letter(rd, self, false)

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
            if st.rudder.closed?
              return
            end

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
            # Re-arm OP_WRITE after a partial write. Before the
            # tryWriteList shortcut, req_write always registered
            # OP_WRITE up front and the registration survived any
            # number of partial writes; on_wrote could no-op here. The
            # shortcut path skips the up-front registration, so we
            # need to add it now or the remaining bytes never get
            # written and the response truncates after one write.
            add_operation(st.rudder, Selector::OP_WRITE)
          end

          def close_rudder(rd)
            @selector.unregister(rd.io)
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

            # Drain inline-write attempts queued by req_write. Calling
            # on_writable directly here is the shortcut: we get to the
            # send() syscall without going through epoll_ctl + select.
            # If the buffer is full, on_writable will re-arm OP_WRITE
            # itself and the rest of the bytes go out via the normal
            # selector path next round.
            while true
              st = @try_write_list.shift
              break if st.nil?
              begin
                on_writable(st)
              rescue Sink
                raise
              rescue => e
                BayLog.error_e(e, "%s Unhandled error on deferred write: rd=%s", @agent, st.rudder)
                raise Sink.new("Unhandled error: %s" % e.message)
              end
            end

            return !selected_map.empty?
          end

          #
          # Wake up the recipient
          #
          def wakeup
            # Non-blocking write: a full pipe means a wake-up byte is already
            # pending, so there is nothing to do. A blocking write here would
            # deadlock the agent — wakeup is called from add_operation on the
            # same thread that drains the pipe in on_waked_up, so if the pipe
            # ever fills (high request rate × multiple add_operation per
            # request) the agent freezes and connections accumulate in
            # CLOSE-WAIT after the client closes.
            begin
              @select_wakeup_pipe[1].write_nonblock([0].pack("N"))
            rescue IO::WaitWritable
              # pipe full — wakeup already pending, OK to drop
            end
          end

          private
          def add_operation(rd, op, to_connect=false)
            ch_op = @operations[rd]
            if ch_op != nil
              ch_op.op |= op
              ch_op.to_connect = (ch_op.to_connect or to_connect)
            else
              @operations[rd] = ChannelOperation.new(rd, op, to_connect)
            end

            wakeup
          end

          def register_channel_ops
            if @operations.empty?
              return 0
            end

            nch = @operations.length
            @operations.each do |rd, rd_op|
              st = get_rudder_state(rd)
              if rd.io.closed?
                # Channel is closed before register operation
                BayLog.debug("%s Try to register closed socket (Ignore)", @agent)
                next
              end

              begin
                io = rd.io
                # BayLog.trace("%s register op=%s st=%s", @agent, self.class.op_mode(rd_op.op), st)
                op = @selector.get_op(io)
                if op == nil
                  @selector.register(io, rd_op.op)
                else
                  new_op = op | rd_op.op
                  # BayLog.trace("%s Already registered rd=%s op=%s update to %s", @agent, rd_op.rudder, self.class.op_mode(op), self.class.op_mode(new_op))
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
                st = get_rudder_state(rd)
                BayLog.error_e(e, "%s Cannot register operation: %s", self.agent, st.rudder)
              end
            end

            @operations.clear
            return nch
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
              if e.kind_of? SystemCallError
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
              @agent.send_error_letter(st.rudder, self, e, false)
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

            @agent.send_accepted_letter(st.rudder, self, client_rd, false)

          end

          def on_connectable(st)
            BayLog.trace("%s onConnectable", self)

            # check connected
            err = st.rudder.io.getsockopt(Socket::SOL_SOCKET, Socket::SO_ERROR).int
            if err != 0
              BayLog.error("Connect failed: errno=%d", err)
              begin
                raise SystemCallError.new("connect", err)
              rescue SystemCallError => e
                @agent.send_error_letter(st.rudder, self, e, false)
              end
            else
              @agent.send_connected_letter(st.rudder, self, false)
            end

          end

          def on_readable(st)
            # Read data

            BayLog.trace("%s on_readable", self)

            begin
              if st.handshaking
                if handshake(st)
                  st.handshaking = false
                else
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
              end

              BayLog.debug("%s read %d bytes", self, len)
              @agent.send_read_letter(st.rudder, self, len, nil, false)

            rescue Exception => e
              BayLog.debug_e(e, "%s Unhandled error", self)
              @agent.send_error_letter(st.rudder, self, e, false)
              return
            end
          end

          def on_writable(st)
            begin
              if st.handshaking
                if handshake(st)
                  st.handshaking = false
                else
                  return NextSocketAction::CONTINUE
                end
              end

              if st.write_queue.empty?
                #raise IOError.new(@agent.to_s + " No data to write: " + st.rudder.to_s)
                BayLog.debug("%s No data to write: tp=%s rd=%s", self, st.transporter, st.rudder)
                return
              end

              # Gather consecutive non-empty bufs into a single
              # write_nonblock call so multiple WriteUnits ride one
              # syscall (and on TLS one SSL_write -> one TLS record).
              # Java caps its writev gather at bufsize; do the same so
              # we don't spend memcpy on bytes the kernel won't accept
              # in this round anyway.
              cap = st.buf_size > 0 ? st.buf_size : 65536

              # Drain any units at the head whose buf has already been
              # emptied by an earlier on_writable in this same
              # receive() pass. Java has no equivalent of wrote_letter(0)
              # to drive consumption of zero-byte units; consume them
              # inline (shift + done()) instead so we don't burn a
              # syscall + letter just to remove a zero-byte placeholder.
              while !st.write_queue.empty? && st.write_queue[0].buf.empty?
                drained = st.write_queue.shift
                drained.done(st.buffer_available?)
              end
              return if st.write_queue.empty?

              i = 0
              done = false
              while i < st.write_queue.length && !done
                wunit = st.write_queue[i]

                # An empty buf can only appear past the head -- the
                # head-drain above removed any leading empties. A mid-
                # batch empty acts as a cap on the gather so the
                # listener for the unit just ahead of it fires before
                # we keep going.
                if wunit.buf.empty?
                  i += 1
                  next
                end

                # Collect consecutive non-empty bufs from index i.
                batch = [wunit]
                total = wunit.buf.bytesize
                j = i + 1
                while j < st.write_queue.length
                  uu = st.write_queue[j]
                  break if uu.buf.empty?
                  sz = uu.buf.bytesize
                  break if total + sz > cap
                  batch << uu
                  total += sz
                  j += 1
                end

                if batch.length == 1
                  BayLog.debug("%s Try to write: rd=%s pkt=%s len=%d adr=%s",
                               self, st.rudder, wunit.tag, wunit.buf.length, wunit.adr)
                  buf_to_write = wunit.buf
                else
                  BayLog.debug("%s Try to gather-write: rd=%s units=%d total=%d",
                               self, st.rudder, batch.length, total)
                  @gather_buf.clear
                  batch.each { |b| @gather_buf << b.buf }
                  buf_to_write = @gather_buf
                end

                begin
                  n = st.rudder.write(buf_to_write)
                rescue OpenSSL::SSL::SSLErrorWaitWritable, IO::WaitWritable => e
                  BayLog.debug_e(e, "%s Cannot write data", self)
                  n = 0
                end

                # Distribute n across the batch units, mirroring the
                # original "send wrote_letter, slice, break on partial"
                # pattern but per-unit.
                remaining = n
                partial = false
                batch.each do |b|
                  sz = b.buf.bytesize
                  if remaining >= sz
                    @agent.send_wrote_letter(st.rudder, self, sz, false)
                    b.buf.slice!(0, sz)
                    remaining -= sz
                  else
                    @agent.send_wrote_letter(st.rudder, self, remaining, false)
                    b.buf.slice!(0, remaining)
                    remaining = 0
                    partial = true
                    break
                  end
                end

                if partial
                  BayLog.debug("%s Wrote %d / %d bytes (Data remains)", self, n, total)
                  done = true
                else
                  i += batch.length
                end
              end

            rescue SystemCallError, IOError, OpenSSL::SSL::SSLError => e
              # OpenSSL::SSL::SSLError doesn't inherit from IOError so
              # without it raw SSL_write failures (e.g. peer abort
              # mid-handshake or mid-record) escape on_writable and
              # the agent treats it as a fatal Sink. Treat it the
              # same way as a plain IO error: send an error letter
              # and let the connection close gracefully.
              BayLog.debug_e(e, "%s IO error", self)
              @agent.send_error_letter(st.rudder, self, e, false)
            end
          end

          def on_waked_up
            # Drain all pending wakeup bytes. Each add_operation call writes 4
            # bytes; under high load this fires several times per request, and
            # since this method runs on the same thread as the producer, only
            # draining 4 bytes per cycle leaves the pipe near-full. Loop until
            # WaitReadable to mirror the PHP port's onWakedUp pattern.
            begin
              while true
                @select_wakeup_pipe[0].read_nonblock(4096)
              end
            rescue IO::WaitReadable
              # fully drained
            end
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

          def handshake(st)
            begin
              # Calls accept API for client socket
              st.rudder.io.accept_nonblock

              BayLog.debug("%s Handshake done (rd=%s)", self, st.rudder)
              app_protocols = st.rudder.io.context.alpn_protocols

              # HELP ME
              #   This code does not work!
              #   We cannot get application protocol name
              proto = nil
              if app_protocols != nil && app_protocols.length > 0
                proto = app_protocols[0]
              end

              return true
            rescue IO::WaitReadable => e
              BayLog.debug("%s Handshake status: read more st=%s", self, st)
              return false
            rescue IO::WaitWritable => e
              BayLog.debug("%s Handshake status: write more st=%s", self, st)
              req_write(st.rudder, "", nil, nil, true)
              return false
            end
          end
        end
      end
    end
  end
end