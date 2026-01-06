require 'baykit/bayserver/rudders/rudder'
require 'baykit/bayserver/util/simple_buffer'

module Baykit
  module BayServer
    module Docker
      module SendFile
        class FileContent

          attr :path
          attr :content
          attr :content_length
          attr_accessor :bytes_loaded
          attr :loaded_time
          attr :waiters

          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Util


          def initialize(path, length)
            @path = path
            @content = ""
            @content_length = length
            @bytes_loaded = 0
            @loaded_time = Time.now.to_i
            @waiters = []
          end

          def is_loaded()
            return @bytes_loaded == @content_length
          end

          def add_waiter(waiter)
            if is_loaded
              wakeup_waiter(waiter)
            else
              waiters << waiter
            end
          end

          def complete()
            @waiters.each do |waiter|
              wakeup_waiter(waiter)
            end
            waiters.clear
          end

          def wakeup_waiter(waiter)
            begin
              waiter.write(" ")
            rescue IOError => e
              BayLog.error_e(e, "Write error: %s", e)
            end
          end
        end
      end
    end
  end
end
