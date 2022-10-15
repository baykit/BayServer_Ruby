require 'baykit/bayserver/util/executor_service'
require 'baykit/bayserver/util/counter'

module Baykit
  module BayServer
      module Train
        class TrainRunner
          include Baykit::BayServer::Util

          # define class instance accessor
          class << self
            attr :exe
          end

          def self.init(num_agents)
            @exe = ExecutorService.new("TrainRunner", num_agents)
          end

          def self.post(train)
            begin
              @exe.submit(train)
              return true
            rescue => e
              BayLog.error_e(e)
              return false
            end
          end
        end
      end
  end
end

