require 'baykit/bayserver/util/reusable'
require 'baykit/bayserver/util/counter'
require 'baykit/bayserver/util/rough_time'
require 'baykit/bayserver/util/object_store'
require 'baykit/bayserver/common/write_unit'

module Baykit
  module BayServer
    module Common
        class RudderState
          include Baykit::BayServer::Util::Reusable  # implements

          include Baykit::BayServer::Util
          class << self
            attr :id_counter
          end
          @id_counter = Counter.new

          attr :id

          attr :rudder
          attr :transporter
          attr_accessor :multiplexer

          attr :last_access_time
          attr_accessor :closing
          attr :read_buf
          attr :buf_size
          attr :write_queue
          attr_accessor :handshaking
          attr_accessor :reading
          attr_accessor :writing
          attr_accessor :bytes_read
          attr_accessor :bytes_wrote
          attr :write_queue_lock
          attr :reading_lock
          attr :writing_lock
          attr_accessor :finale

          attr_accessor :accepting
          attr_accessor :connecting
          attr_accessor :skip_formalities

          # If true, the SpiderMultiplexer re-arms TCP_QUICKACK on this
          # socket after every read so the kernel sends the ACK
          # immediately instead of holding it on the delayed-ACK timer.
          # Only meaningful for warp upstream connections to backends
          # that keep Nagle on (= php-fpm and friends): the 40ms
          # delayed-ACK timer combined with backend Nagle stalls
          # 10KB-class responses at ~177 rps.
          #
          # Inbound (= client-facing) sockets don't need this -- the
          # client is a wrk / browser / load balancer that sets
          # TCP_NODELAY itself, and setsockopt per read measurably
          # costs CPU at high rps -- so warp code sets the flag
          # explicitly when wiring up the upstream socket, leaving
          # inbound sockets untouched.
          attr_accessor :quick_ack

          # Per-connection ObjectStore pool for WriteUnits. write_queue
          # holds in-flight units; @write_unit_store is the free-list,
          # both for the same connection. The store persists across
          # rents of this RudderState (= our reset() does NOT touch
          # the store) so cached WriteUnits stay reusable for the next
          # connection that takes this state.
          def initialize
            @write_unit_store = Baykit::BayServer::Util::ObjectStore.new(
              lambda { Baykit::BayServer::Common::WriteUnit.new })
          end

          def rent_write_unit
            @write_unit_store.rent
          end

          def return_write_unit(u)
            @write_unit_store.Return(u)
          end

          def init(rd, tp = nil, timeout_sec = 0)
            @id = RudderState.id_counter.next
            @rudder = rd
            @transporter = tp
            @timeout_sec = timeout_sec

            if tp != nil
              @buf_size = tp.get_read_buffer_size
              @handshaking = tp.secure() ? true : false
            else
              @buf_size = 8192
              @handshaking = false
            end
            # IO#read_nonblock(maxlen, outbuf) shrinks outbuf to actual
            # bytes read but the underlying RString buffer keeps its
            # grown capacity across reads, so we just need an empty
            # String once and let the first few reads grow it to the
            # steady-state size (typically << @buf_size for 128B-1KB
            # requests). Pre-allocating @buf_size bytes was wasted
            # work because (a) shrinking via read still leaves the
            # capacity, and (b) the original `bytesize != @buf_size`
            # guard was always true after the first read so the
            # 8 KB alloc fired on every rent anyway.
            @read_buf = "".b if @read_buf.nil?
            @write_queue ||= []
            @write_queue_lock ||= Mutex.new
            @reading_lock ||= Mutex.new
            @writing_lock ||= Mutex.new

            @accepting = false
            @connecting = false
            @reading = false
            @writing = false
            @bytes_read = 0
            @bytes_wrote = 0
            @quick_ack = false
          end

          def to_s
            str = "st(rd=#{@rudder} mpx=#{@multiplexer} tp=#{@transporter})"
            return str
          end

          #########################################
          # Implements Reusable
          #########################################
          def reset()
            @id = 0
            @rudder = nil
            @transporter = nil
            @multiplexer = nil

            @last_access_time = 0
            @closing = false
            # Clear instead of re-allocating so the next rent reuses the
            # backing storage; the matching init() also lazy-allocates.
            # @read_buf.clear if @read_buf
            @write_queue.clear if @write_queue
            @bytes_read = 0
            @bytes_wrote = 0
            @finale = false
            @reading = false
            @writing = false
            @timeout_sec = 0
            @quick_ack = false
          end

          #########################################
          # Custom methods
          #########################################

          def access
            @last_access_time = Baykit::BayServer::Util::RoughTime.current_time_secs
          end

          # Sum of pending bytes across queued WriteUnits. Used by
          # SpiderMultiplexer's flush threshold so we can defer the
          # OP_WRITE registration until either the caller asked for a
          # flush or enough data has accumulated to be worth a syscall.
          def remaining
            total = 0
            @write_queue.each { |u| total += u.remaining }
            total
          end

          # Returns whether the multiplexer's internal write buffer
          # for this connection still has room. Capacity is the
          # ship_buffer_size harbor parameter; true means pending
          # data in the write queue is at most ship_buffer_size.
          def buffer_available?
            remaining <= BayServer.harbor.ship_buffer_size
          end

          def end
            @finale = true
          end

      end
    end
  end
end