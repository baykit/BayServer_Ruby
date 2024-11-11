require 'baykit/bayserver/util/executor_service'
require 'baykit/bayserver/util/counter'

module Baykit
  module BayServer
      module Train
        class TrainRunner
          include Baykit::BayServer
          include Baykit::BayServer::Common


          class << self
            attr :runner
          end

          @runner = VehicleRunner.new


          ######################################################
          # Class methods
          ######################################################

          def self.init(max_trains)
            @runner.init(max_trains)
          end

          def self.post(agt_id, train)
            BayLog.debug("agt#%d post train: thread=%s train=%s", agt_id, Thread.current.name, train);
            @runner.post(agt_id, train)
          end

        end
      end
  end
end

