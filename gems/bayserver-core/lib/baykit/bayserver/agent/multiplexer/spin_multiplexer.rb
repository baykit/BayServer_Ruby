require 'baykit/bayserver/common/recipient'
require 'baykit/bayserver/rudders/rudder'
require 'baykit/bayserver/rudders/io_rudder'

require 'baykit/bayserver/agent/multiplexer/multiplexer_base'
require 'baykit/bayserver/agent/timer_handler'

module Baykit
  module BayServer
    module Agent
      module Multiplexer
        class SpinMultiplexer < Baykit::BayServer::Agent::Multiplexer::MultiplexerBase
          include Baykit::BayServer::Agent::TimerHandler #implements

          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Util

          class Lapper  # abstract class

            attr :state
            attr :last_access

            def initialize(state)
              @state = state
              access
            end

            def access
              @last_access = Time.now.tv_sec
            end

            def lap()
              raise NotImplementedError
            end

            def next
              raise NotImplementedError
            end

            def ==(other)
              other.state == @state
            end
          end

          class ReadIOLapper < Lapper

            attr :agent

            def initialize(agt, st)
              super(st)
              @agent = agt
              st.rudder.set_non_blocking
            end

            def lap
              spun = false

              begin
                infile = @state.rudder.io
                eof = false

                begin
                  n = @state.rudder.read(@state.read_buf, @state.buf_size)
                  #infile.sysread(@state.buf_size, @state.read_buf)
                rescue EOFError => e
                  @state.read_buf.clear
                  eof = true
                rescue Errno::EAGAIN => e
                  BayLog.debug("%s %s", @agent, e)
                  return true
                end

                if @state.read_buf.length == 0
                  if !eof
                    return true
                  else
                    BayLog.debug("%s Spin read: EOF\\(^o^)/ rd=%s", @agent, infile)
                  end
                end

                @agent.send_read_letter(@state, @state.read_buf.length, nil, false)
                return false

              rescue Exception => e
                @agent.send_error_letter(@state, e, false)
                return false
              end
            end

            def next

            end

          end

          attr :spin_count
          attr :running_list
          attr :running_list_lock

          def initialize(agt)
            super(agt)
            @spin_count = 0
            @running_list = []
            @running_list_lock = Mutex.new
            @agent.add_timer_handler(self)
          end
          def to_s
            return "SpnMpx[#{@agent}]"
          end

          #########################################
          # Implements Multiplexer
          #########################################

          def req_accept(rd)
            raise NotImplementedError.new
          end

          def req_connect(rd, adr)
            raise NotImplementedError.new
          end

          def req_read(rd)
            st = get_rudder_state(rd)
            if st == nil
              BayLog.error("%s Invalid rudder", self)
              return
            end

            need_read = false
            st.reading_lock.synchronize do
              if not st.reading
                need_read = true
                st.reading = true
              end
            end

            if need_read
              next_read(st)
            end
          end

          def req_write(rd, buf, len, adr, tag, &lis)
            st = get_rudder_state(rd)
            if st == nil
              BayLog.warn("Invalid rudder")
              lis.call()
            end

            unt = WriteUnit.new(buf, adr, tag, &lis)
            st.write_queue_lock.synchronize do
              st.write_queue << unt
            end
            st.access

            need_write = false
            st.writing_lock.synchronize do
              if not st.writing
                need_write = true
                st.writing = true
              end
            end

            if need_write
              next_write(st)
            end
          end

          def req_end(rd)
            st = get_rudder_state(rd)
            st.finale = true
          end

          def req_close(rd)
            st = get_rudder_state(rd)
            st.closing = true
            close_rudder(st)
            @agent.send_closed_letter(st, false)
          end


          def shutdown
            wakeup
          end

          def is_non_blocking
            return false
          end

          def use_async_api
            return false
          end


          def cancel_read(st)
            st.reading_lock.synchronize do
              BayLog.debug("%s Reading off %s", agent, st.rudder)
              st.reading = false
            end
            remove_from_running_list(st)
          end

          def cancel_write(st)
          end

          def next_accept(st)
          end

          def next_read(st)
            lpr = ReadIOLapper.new(@agent, st)
            lpr.next

            add_to_running_list(lpr)
          end

          def next_write(st)
          end

          def on_busy
            BayLog.debug("%s onBusy", agent)
            BayServer::anchorable_port_map.keys.each do |rd|

            end
          end

          def on_free
            BayLog.debug("%s onFree aborted=%s", agent, agent.aborted);
            if agent.aborted
              return
            end

            BayServer.anchorable_port_map.keys.each do |rd|

            end
          end

          def close_rudder(st)
            remove_from_running_list(st)
            super
          end

          #########################################
          # Implements TimerHandler
          #########################################

          def on_timer
            #stop_timeout_spins
          end

          #########################################
          # Custom methods
          #########################################
          def is_empty
            return @running_list.empty?
          end

          def process_data
            if is_empty
              return false
            end

            all_spun = true
            remove_list = []
            @running_list.length.downto(1) do |i|
              lpr = @running_list[i-1]
              st = lpr.state
              spun = lpr.lap
              st.access

              all_spun = all_spun & spun
            end

            if all_spun
              @spin_count += 1
              if @spin_count > 10
                sleep(0.01)
              else
                @spin_count = 0
              end
            end

            return true

          end

          #########################################
          # Private methods
          #########################################
          private

          def remove_from_running_list(st)
            BayLog.debug("remove: %s", st.rudder)
            @running_list_lock.synchronize do
              @running_list.delete_if do |lpr |
                lpr.state == st
              end
            end
          end

          def add_to_running_list(lpr)
            BayLog.debug("add: %s", lpr.state.rudder)
            @running_list_lock.synchronize do
              if !@running_list.include?(lpr)
                @running_list << lpr
              end
            end
          end
        end
      end
    end
  end
end