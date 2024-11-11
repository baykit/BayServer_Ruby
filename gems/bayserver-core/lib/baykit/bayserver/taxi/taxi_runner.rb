require 'baykit/bayserver/bayserver'
require 'baykit/bayserver/common/vehicle_runner'

module Baykit
  module BayServer
    module Taxi
      class TaxiRunner
        include Baykit::BayServer
        include Baykit::BayServer::Common


        class << self
          attr :runner
        end

        @runner = VehicleRunner.new


        ######################################################
        # Class methods
        ######################################################

        def self.init(max_taxis)
          @runner.init(max_taxis)
        end

        def self.post(agt_id, txi)
          BayLog.debug("agt#%d post taxi: thread=%s taxi=%s", agt_id, Thread.current.name, txi);
          @runner.post(agt_id, txi)
        end

      end
    end
  end
end

