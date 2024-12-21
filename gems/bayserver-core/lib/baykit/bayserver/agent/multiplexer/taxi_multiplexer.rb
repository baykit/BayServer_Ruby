require 'baykit/bayserver/sink'
require 'baykit/bayserver/rudders/io_rudder'

require 'baykit/bayserver/agent/multiplexer/multiplexer_base'
require 'baykit/bayserver/taxi/taxi'
require 'baykit/bayserver/taxi/taxi_runner'


module Baykit
  module BayServer
    module Agent
      module Multiplexer
        class TaxiMultiplexer < MultiplexerBase

          class TaxiForMpx < Baykit::BayServer::Taxi::Taxi
            attr :rudder_state
            attr :for_read
            def initialize(st, for_read)
              @rudder_state = st
              @for_read = for_read
            end
            def depart
              if @for_read
                @rudder_state.multiplexer.do_next_read(@rudder_state)
              else
                @rudder_state.multiplexer.do_next_write(@rudder_state)
              end
            end

            def on_timer
              if @rudder_state.transporter != nil
                @rudder_state.transporter.check_timeout(@rudder_state.rudder, -1)
              end
            end
          end

          include Baykit::BayServer::Agent::Multiplexer

          include Baykit::BayServer
          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Util
          include Baykit::BayServer::Taxi

          def initialize(agt)
            super
          end
          def to_s
            return "TaxiMpx[#{@agent}]"
          end


          #########################################
          # Implements Multiplexer
          #########################################

          def req_accept(rd)
            raise Sink.new
          end

          def req_connect(rd, adr)
            raise Sink.new
          end

          def req_read(rd)
            st = get_rudder_state(rd)
            if st == nil
              return
            end

            BayLog.debug("%s reqRead rd=%s state=%s", @agent, st.rudder, st);
            need_read = false
            st.reading_lock.synchronize do
              if !st.reading
                need_read = true
                st.reading = true
              end
            end

            if need_read
              next_run(st, true)
            end

            st.access
          end

          def req_write(rd, buf, adr, tag, &lis)
            st = get_rudder_state(rd)
            BayLog.debug("%s reqWrite st=%s", @agent, st)

            if st == nil || st.closed
              BayLog.warn("%s Channel is closed: %s", @agent, rd)
              lis.call
              return
            end

            unt = WriteUnit.new(buf, adr, tag, &lis)
            st.write_queue_lock.synchronize do
              st.write_queue << unt
            end

            need_write = false
            st.writing_lock.synchronize do
              if !st.writing
                need_write = true
                st.writing = true
              end
            end

            if need_write
              next_run(st, false)
            end

            st.access
          end

          def req_close(rd)
            st = get_rudder_state(rd)
            BayLog.debug("%s reqClose st=%s", @agent, st);
            close_rudder(st)
            @agent.send_closed_letter(st, false)
            st.access
          end

          def cancel_read(st)

          end

          def cancel_write(st)

          end

          def next_accept(st)
            raise Sink.new
          end

          def next_read(st)
            next_run(st, true)
          end

          def next_write(st)
            next_run(st, false)
          end

          def is_non_blocking()
            return false
          end

          def use_async_api()
            return false
          end

          def next_run(st, for_read)
            BayLog.debug("%s Post next run: %s", self, st)

            TaxiRunner.post(@agent.agent_id, TaxiForMpx.new(st, for_read))
          end

          def do_next_read(st)
            st.access
            begin
              len = st.rudder.read(st.read_buf, st.buf_size)
              if len <= 0
                len = 0
              end
              @agent.send_read_letter(st, len, nil, true)

            rescue Exception => e
              @agent.send_error_letter(st, e, true)
            end
          end

          def do_next_write(st)
            st.access
            begin
              if st.write_queue.empty?
                raise Sink("%s write queue is empty", self)
              end

              u = st.write_queue[0]
              if u.buf.length == 0
                len = 0
              else
                len = st.rudder.write(u.buf)
                u.buf.slice!(0, len)
              end
              @agent.send_wrote_letter(st, len, true)

            rescue Exception => e
              @agent.send_error_letter(st, e, true)
            end
          end
        end
      end
    end
  end
end