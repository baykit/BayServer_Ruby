require 'baykit/bayserver/agent/spin_handler'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/reusable'
require 'baykit/bayserver/util/valve'
require 'baykit/bayserver/util/postman'

module Baykit
  module BayServer
    module Agent
        module Transporter
          class SpinWriteTransporter < Baykit::BayServer::Agent::SpinHandler
            include Baykit::BayServer::Util::Valve # implements
            include Baykit::BayServer::Util::Reusable # implements
            include Baykit::BayServer::Util::Postman # implements

            include Baykit::BayServer::Util

            attr :spin_handler
            attr :data_listener
            attr :outfile
            attr :write_queue
            attr :lock


            def initialize()
              @write_queue = []
              @lock = Mutex.new()
            end

            def init(spin_hnd, outfile, lis)
              @spin_handler = spin_hnd
              @data_listener = lis
              @outfile = outfile
            end

            def to_s
              data_listener.to_s()
            end

            ######################################################
            # Implements Reusable
            ######################################################

            def reset()
              @data_listener = nil
              @outfile = nil
            end

            ######################################################
            # Implements SpinListener
            ######################################################

            def lap()
              begin

                buf = nil
                @lock.synchronize do
                  if @write_queue.empty?
                    BayLog.warn("%s Write queue empty", self)
                    return NextSocketAction::SUSPEND
                  end
                  buf = @write_queue[0]
                end

                len = @outfile.syswrite(buf)

                if len == 0
                  return NextSocketAction::CONTINUE
                elsif len < buf.length
                  buf[0 .. len-1] = ""
                  return NextSocketAction::CONTINUE
                end

                @lock.synchronize do
                  @write_queue.delete_at(0)
                  if @write_queue.empty?
                    return NextSocketAction::SUSPEND
                  else
                    return NextSocketAction::CONTINUE
                  end
                end

              rescue Exception => e
                BayLog.error_e(e)
                close()
                return NextSocketAction::CLOSE
              end
            end

            def check_timeout(duration_sec)
              return false
            end

            def close()
              if @outfile != nil
                @outfile.close()
              end
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
            def post(bytes, tag)
              @lock.synchronize do
                empty = @write_queue.empty?
                @write_queue << bytes
                if empty
                  open_valve()
                end
              end
            end

          end
        end
    end
  end
end
