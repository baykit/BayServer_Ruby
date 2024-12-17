require 'baykit/bayserver/rudders/io_rudder'

require 'baykit/bayserver/agent/multiplexer/multiplexer_base'
require 'baykit/bayserver/agent/multiplexer/job_multiplexer_base'


module Baykit
  module BayServer
    module Agent
      module Multiplexer
        class JobMultiplexer < JobMultiplexerBase
          include Baykit::BayServer::Agent::TimerHandler #implements
          include Baykit::BayServer::Common::Recipient  # implements
          include Baykit::BayServer::Agent::Multiplexer

          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Util

          def initialize(agt, anchorable)
            super
          end
          def to_s
            return "JobMpx[#{@agent}]"
          end


          #########################################
          # Implements Multiplexer
          #########################################

          def req_accept(rd)
            BayLog.debug("%s reqAccept isShutdown=%s", @agent, @agent.aborted)
            if @agent.aborted
              return
            end

            st = get_rudder_state(rd)

            Thread.new do
              begin
                if @agent.aborted
                  next
                end

                begin
                  client_skt, adr = rd.io.accept
                rescue Exception => e
                  @agent.send_accepted_letter(st, nil, e, true)
                  next
                end

                BayLog.debug("%s Accepted skt=%s", @agent, client_skt)
                if agent.aborted
                  BayLog.error("%s Agent is not alive (close)", @agent);
                  client_skt.close
                else
                  @agent.send_accepted_letter(st, IORudder.new(client_skt), nil, true)
                end

              rescue Exception => e
                BayLog.fatal_e(e)
                @agent.shutdown
              end
            end

          end


          def req_connect(rd, adr)
            st = get_rudder_state(rd)
            BayLog.debug("%s reqConnect adr=%s rd=%s chState=%s", @agent, adr.canonname, rd, st)

            Thread.new do
              begin
                rd.io.connect(adr)
                BayLog.debug("%s Connected rd=%s", @agent, rd)
                @agent.send_connected_letter(st, nil, false)
              rescue Exception => e
                @agent.send_connected_letter(st, e, false)
                return
              end
            end

            st.connecting = true
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
              next_read(st)
            end

            st.access
          end

          def req_write(rd, buf, adr, tag, &lis)
            st = get_rudder_state(rd)
            BayLog.debug("%s reqWrite st=%s", @agent, st)

            if st == nil || st.closed
              BayLog.warn("%s Channel is closed: %s", @agent, rd)
              lis.call()
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
              next_write(st)
            end

            st.access
          end

          def req_close(rd)
            st = get_rudder_state(rd)
            BayLog.debug("%s reqClose st=%s", @agent, st);

            if st == nil
              BayLog.warn("%s channel state not found: %s", @agent, rd)
              return
            end

            Thread.new do
              begin
                st = get_rudder_state(rd)
                if st == nil
                  BayLog.debug("%s Rudder is already closed: rd=%s", @agent, rd)
                  next
                end

                close_rudder(st)
              rescue Exception => e
                BayLog.fatal_e(e)
                @agent.shutdown
              end
            end

            st.access
          end

          def cancel_read(st)

          end

          def cancel_write(st)

          end

          def next_accept(st)
            req_accept(st.rudder)
          end

          def next_read(st)
            Thread.new do
              if st.closed
                #channel is already closed
                BayLog.debug("%s Rudder is already closed: rd=%s", @agent, st.rudder);
                next
              end

              begin
                if st.handshaking
                  # Calls accept API for client socket
                  st.rudder.io.accept
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
                end

                BayLog.debug("%s Try to Read (rd=%s)", @agent, st.rudder)
                begin
                  n = st.rudder.read(st.read_buf, st.buf_size)
                rescue EOFError => e
                  n = 0
                  st.read_buf.clear
                end

                @agent.send_read_letter(st, n, nil, nil, true)

              rescue Exception => e
                @agent.send_read_letter(st, -1, nil, e, true)
              end
            end
          end

          def next_write(st)
            Thread.new do
              BayLog.debug("%s next write st=%s", @agent, st)

              if st == nil || st.closed
                BayLog.warn("%s Channel is closed: %s", @agent, st.rudder)
                next
              end

              u = st.write_queue[0]
              BayLog.debug("%s Try to write: pkt=%s buflen=%d closed=%s", self, u.tag, u.buf.length, st.closed);

              n = 0
              begin
                if !st.closed && u.buf.length > 0
                  n = st.rudder.write(u.buf)
                  u.buf.slice!(0, n)
                end
              rescue Exception => e
                @agent.send_wrote_letter(st, -1, e, true)
                next
              end

              @agent.send_wrote_letter(st, n, nil, true)
            end
          end

          def is_non_blocking()
            return false
          end

          def use_async_api()
            return false
          end
        end
      end
    end
  end
end