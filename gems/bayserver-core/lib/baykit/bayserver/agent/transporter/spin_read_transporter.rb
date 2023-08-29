require 'baykit/bayserver/agent/spin_handler'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/valve'

module Baykit
  module BayServer
    module Agent
        module Transporter
          class SpinReadTransporter
            include Baykit::BayServer::Agent::SpinHandler::SpinListener # implements
            include Baykit::BayServer::Util::Valve # implements
            include Baykit::BayServer::Util

            attr :spin_handler
            attr :data_listener
            attr :infile
            attr :read_buf
            attr :total_read
            attr :file_len
            attr :timeout_sec
            attr :eof_checker
            attr :is_closed

            def initialize(buf_size)
              @read_buf = StringUtil.alloc(buf_size)
            end

            def init(spin_hnd, lis, infile, limit, timeout_sec, eof_checker)
              @spin_handler = spin_hnd
              @data_listener = lis
              @infile = infile
              @file_len = limit
              @total_read = 0
              @timeout_sec = timeout_sec
              @eof_checker = eof_checker
              @is_closed = false
            end

            def to_s
              data_listener.to_s()
            end

            ######################################################
            # Implements Reusable
            ######################################################

            def reset()
              @data_listener = nil
              @infile = nil
            end

            ######################################################
            # Implements SpinListener
            ######################################################

            def lap()
              begin
                @infile.sysread(@buf_size, @read_buf)

                if @read_buf.length == 0
                  return NextSocketAction::CONTINUE, true
                end
                @total_read += @read_buf.length

                next_act = @yacht.notify_read(@read_buf)

                if @total_read == @file_len
                  @data_listener.notify_eof()
                  close()
                  return NextSocketAction::CLOSE, false
                end

                return next_act, false
              rescue Exception => e
                BayLog.error_e(e)
                close()
                return NextSocketAction::CLOSE, false
              end
            end

            def check_timeout(duration_sec)
              return duration_sec > @timeout_sec
            end

            def close()
              if @infile != nil
                @infile.close()
              end
              @data_listener.notify_close()
              @is_closed = true
            end

            ######################################################
            # Implements Valve
            ######################################################

            def open_valve()
              @spin_handler.ask_to_callback(self)
            end

            ######################################################
            # Other methods
            ######################################################


          end

        end
    end
  end
end
