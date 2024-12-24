
module Baykit
  module BayServer
    module Agent
      module Multiplexer
        class RudderState
          attr :rudder
          attr :transporter
          attr_accessor :multiplexer

          attr :last_access_time

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
          attr_accessor :closed
          attr_accessor :finale

          attr_accessor :accepting
          attr_accessor :connecting


          def initialize(rd, tp = nil, timeout_sec = 0)
            @rudder = rd
            @transporter = tp
            @closed = false
            @timeout_sec = timeout_sec

            if tp != nil
              @buf_size = tp.get_read_buffer_size
              @handshaking = tp.secure() ? true : false
            else
              @buf_size = 8192
              @handshaking = false
            end
            @read_buf = " ".b * @buf_size

            @accepting = false
            @connecting = false
            @write_queue = []
            @write_queue_lock = Mutex::new
            @reading_lock = Mutex::new
            @writing_lock = Mutex::new
            @reading = false
            @writing = false
            @bytes_read = 0
            @bytes_wrote = 0
          end

          def to_s
            str = "st(rd=#{@rudder} mpx=#{@multiplexer} tp=#{@transporter})"
            return str
          end


          def access
            @last_access_time = Time.now.tv_sec
          end

          def end
            @finale = true
          end

        end
      end
    end
  end
end