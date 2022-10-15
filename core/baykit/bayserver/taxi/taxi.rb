require 'baykit/bayserver/util/counter'
module Baykit
  module BayServer
    module Taxi
      class Taxi
        include Baykit::BayServer::Util
        #
        # abstract method
        #
        # depart()
        #

        class << self
          attr :taxi_id_counter
        end
        @taxi_id_counter = Counter.new()

        attr :taxi_id;

        def initialize
          @taxi_id = Taxi.taxi_id_counter.next()
        end

        def to_s()
          return "Taxi##{@taxi_id}"
        end

        def run()
          BayLog.trace("%s Start taxi on: %s", self, Thread.current.name);
          self.depart();
          BayLog.trace("%s End taxi on: %s", self, Thread.current.name);
        end

      end
    end
  end
end

