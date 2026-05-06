require 'baykit/bayserver/util/reusable'
require 'baykit/bayserver/util/counter'
require 'baykit/bayserver/util/rough_time'

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

          def initialize

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
            # Reuse the read_buf, write_queue, and per-state Mutexes from
            # the previous rent of this RudderState if they exist -- reset
            # already clears them in place but the previous init
            # unconditionally re-allocated. The 8 KB read_buf was the
            # largest single per-connection alloc on the file-serving hot
            # path. Lazy-allocate on first init only.
            if @read_buf.nil? || @read_buf.bytesize != @buf_size
              @read_buf = " ".b * @buf_size
            end
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
            @read_buf.clear if @read_buf
            @write_queue.clear if @write_queue
            @bytes_read = 0
            @bytes_wrote = 0
            @finale = false
            @reading = false
            @writing = false
            @timeout_sec = 0
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
            @write_queue.each { |u| total += u.buf.bytesize }
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