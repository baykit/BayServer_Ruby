require 'baykit/bayserver/taxi/taxi'
require 'baykit/bayserver/taxi/taxi_runner'
require 'baykit/bayserver/agent/next_socket_action'

require 'baykit/bayserver/util/valve'
require 'baykit/bayserver/util/string_util'


module Baykit
  module BayServer
    module Tours
      class ReadFileTaxi < Baykit::BayServer::Taxi::Taxi
        include Baykit::BayServer::Util::Valve #implements

        include Baykit::BayServer::Agent
        include Baykit::BayServer::Taxi
        include Baykit::BayServer::Util

        attr :infile
        attr :ch_valid
        attr :data_listener
        attr :buf
        attr :buf_size
        attr :running
        attr :lock
        attr :agent_id

        def initialize(agt_id, buf_size)
          super()
          @buf_size = buf_size
          @buf = StringUtil.alloc(buf_size)
          @lock = Monitor.new()
          @agent_id = agt_id
        end

        def to_s()
          return super.to_s() + " " + @data_listener.to_s()
        end

        def init(infile, data_listener)
          @data_listener = data_listener
          @infile = infile
          @ch_valid = true
        end

        ######################################################
        # implements Valve
        ######################################################

        def open_valve()
          @lock.synchronize do
            next_run()
          end
        end

        ######################################################
        # implements Taxi
        ######################################################

        def depart()
          @lock.synchronize do
            begin
              @buf.clear()
              @infile.read(@buf_size, @buf)

              if @buf.length == 0
                @data_listener.notify_eof()
                close()
                return
              end

              act = @data_listener.notify_read(@buf, nil)

              @running = false
              if act == NextSocketAction::CONTINUE
                next_run()
              end

            rescue Exception => e
              BayLog.error_e(e)
              close()
            end
          end
        end


        def next_run()
          if @running
            # If running, not posted because next run exists
            return
          end
          @running = true
          TaxiRunner.post(@agent_id, self)
        end

        def close()
          @ch_valid = false
          @infile.close()
          @data_listener.notify_close()
        end
      end
    end
  end
end
