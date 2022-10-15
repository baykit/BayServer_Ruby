require 'baykit/bayserver/util/executor_service'

module Baykit
  module BayServer
    module Taxi
      class TaxiRunner
        include Baykit::BayServer::Util

        # define class instance accessor
        class << self
          attr :exe
        end

        def TaxiRunner.init(num_agents)
          @exe = ExecutorService.new("TaxiRunner", num_agents)
        end

        def TaxiRunner.post(taxi)
          begin
            @exe.submit(taxi)
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

