require 'baykit/bayserver/sink'
require 'baykit/bayserver/taxi/taxi'
require 'baykit/bayserver/taxi/taxi_runner'
require 'baykit/bayserver/util/valve'
require 'baykit/bayserver/util/postman'

module Baykit
  module BayServer
    module Docker
      module BuiltIn
        class WriteFileTaxi < Baykit::BayServer::Taxi::Taxi
          include Baykit::BayServer::Util::Valve   # implements
          include Baykit::BayServer::Util::Postman  # implements

          include Baykit::BayServer::Taxi

          attr :outfile
          attr :ch_valid
          attr :data_listener
          attr :write_queue
          attr :lock

          def initialize()
            super
            @write_queue = []
            @lock = Mutex.new()
          end

          def init(out, data_listener)
            @outfile = out
            @data_listener = data_listener
            @ch_valid = true
          end

          def to_s()
            return super.to_s + " " + @data_listener.to_s
          end

          ######################################################
          # Implements Resumable
          ######################################################
          def open_valve()
            next_run()
          end

          ######################################################
          # Implements Taxi
          ######################################################

          def depart()
            begin
              while true
                buf = nil

                empty = nil
                @lock.synchronize do
                  empty = @write_queue.empty?
                  if !empty
                    buf = @write_queue[0]
                    @write_queue.delete_at(0)
                  end
                end

                if empty
                  break
                end

                @outfile.syswrite(buf)

                empty = nil
                @lock.synchronize do
                  empty = @write_queue.empty?
                end

                if !empty
                  next_run()
                end
              end
            rescue StandardError => e
              BayLog.error_e(e)
            end
          end

          def post(data, adr, tag)
            @lock.synchronize do
              empty = @write_queue.empty?
              @write_queue.append(data)
              if empty
                open_valve()
              end
            end
          end

          def next_run()
            TaxiRunner.post(self)
          end
        end
      end
    end
  end
end
