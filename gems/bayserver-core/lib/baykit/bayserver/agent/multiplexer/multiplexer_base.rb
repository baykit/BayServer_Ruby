require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/common/multiplexer'

module Baykit
  module BayServer
    module Agent
      module Multiplexer
        # All collections owned by this base class (`@rudders`,
        # `@channel_count`) and the per-state collections it touches
        # (`st.write_queue`) are accessed only by the agent's own event
        # loop -- in multi_core mode each agent is a forked process, in
        # thread mode each agent owns its own multiplexer instance. The
        # write path is also entirely agent-driven (req_write, on_wrote
        # via the letter loop, on_writable). There is no contender, so
        # we drop the Mutex#synchronize wrappers from every read / write
        # site below; the locks remain in `attr :rudders_lock`/`:lock`
        # for backward compatibility with any external caller, but the
        # hot path no longer pays for them.
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
            @rudders[rd.key] = st
            @channel_count += 1
            st.access()
          end

          def remove_rudder_state(rd)
            @rudders.delete(rd.key())
            @channel_count -= 1
          end

          def get_rudder_state(rd)
            return find_rudder_state_by_key(rd.key)
          end

          def get_transporter(rd)
            return get_rudder_state(rd).transporter
          end

          def consume_oldest_unit(st)
            return false if st.write_queue.empty?
            u = st.write_queue.shift()
            u.done(st.buffer_available?)
            return true
          end

          def close_rudder(rd)
            BayLog.debug("%s closeRd %s", agent, rd)

            begin
              rd.close()
            rescue IOError => e
              BayLog.error_e(e)
            end

          end

          def is_busy()
            return @channel_count >= @agent.max_inbound_ships
          end


          #########################################
          # Custom methods
          #########################################

          def find_rudder_state_by_key(key)
            return @rudders[key]
          end

          def close_timeout_sockets
            if @rudders.empty?
              return
            end

            close_list = []
            remove_list = []
            copied = @rudders.values
            now = Time.now.tv_sec

            copied.each do |st|
              # Drop rudders that were closed elsewhere without going through
              # remove_rudder_state, so @rudders does not grow without bound.
              if st.rudder.closed?
                remove_list << st.rudder
                next
              end
              if st.transporter != nil
                duration =  now - st.last_access_time
                if st.transporter.check_timeout(st.rudder, duration)
                  BayLog.debug("%s timeout: ch=%s", @agent, st.rudder)
                  close_list << st
                end
              end
            end

            remove_list.each do |rd|
              remove_rudder_state(rd)
            end

            close_list.each do |st|
              req_close(st.rudder)
            end
          end

          def close_all()
            copied = @rudders.values
            copied.each do |st|
              if st.rudder != @agent.command_receiver.rudder
                close_rudder(st.rudder)
              end
            end
          end
        end
      end
    end
  end
end
