require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/common/multiplexer'

module Baykit
  module BayServer
    module Agent
      module Multiplexer
        class MultiplexerBase
          include Baykit::BayServer::Common::Multiplexer # implements
          include Baykit::BayServer

          attr :channel_count
          attr :agent
          attr :rudders
          attr :rudders_lock
          attr :lock

          def initialize(agt)
            @agent = agt
            @channel_count = 0
            @rudders = {}
            @rudders_lock = Mutex::new
            @lock = Mutex::new
          end

          #########################################
          # Implements Multiplexer
          #########################################

          def add_rudder_state(rd, st)
            st.multiplexer = self
            @rudders_lock.synchronize do
              @rudders[rd.key] = st
            end
            @channel_count += 1
            st.access()
          end

          def remove_rudder_state(rd)
            @rudders_lock.synchronize do
              @rudders.delete(rd.key())
            end
            @channel_count -= 1
          end

          def get_rudder_state(rd)
            return find_rudder_state_by_key(rd.key)
          end

          def get_transporter(rd)
            return get_rudder_state(rd).transporter
          end

          def consume_oldest_unit(st)
            u = nil
            st.write_queue_lock.synchronize do
              if st.write_queue.empty?
                return false
              end
              u = st.write_queue.shift()
            end
            u.done()
            return true
          end

          def close_rudder(st)
            BayLog.debug("%s closeRd %s state=%s closed=%s", agent, st.rudder, st, st.closed)

            begin
              st.rudder.close()
            rescue IOError => e
              Baylog.error_e(e)
            end

          end

          def is_busy()
            return @channel_count >= @agent.max_inbound_ships
          end


          #########################################
          # Custom methods
          #########################################

          def find_rudder_state_by_key(key)
            @rudders_lock.synchronize do
              return @rudders[key]
            end
          end

          def close_timeout_sockets
            if @rudders.empty?
              return
            end

            close_list = []
            copied = nil
            @rudders_lock.synchronize do
              copied = @rudders.values
            end
            now = Time.now.tv_sec

            copied.each do |st|
              if st.transporter != nil
                duration =  now - st.last_access_time
                if st.transporter.check_timeout(st.rudder, duration)
                  BayLog.debug("%s timeout: ch=%s", @agent, st.rudder)
                  close_list << st
                end
              end
            end

            close_list.each do |st|
              req_close(st.rudder)
            end
          end

          def close_all()
            copied = nil
            @rudders_lock.synchronize do
              copied = @rudders.values
            end
            copied.each do |st|
              if st.rudder != @agent.command_receiver.rudder
                close_rudder(st)
              end
            end
          end
        end
      end
    end
  end
end