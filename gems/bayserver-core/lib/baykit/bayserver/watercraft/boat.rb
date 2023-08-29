require 'baykit/bayserver/agent/transporter/transporter'
require 'baykit/bayserver/agent/transporter/data_listener'
require 'baykit/bayserver/util/reusable'
require 'baykit/bayserver/util/counter'

module Baykit
  module BayServer
      module WaterCraft
        class Boat
          include Baykit::BayServer::Agent::Transporter::DataListener # implements
          include Baykit::BayServer::Util::Reusable  # implements

          include Baykit::BayServer::Util


          # class variables
          class << self
            attr :oid_counter
            attr :boat_id_counter
          end
          @oid_counter = Counter.new
          @boat_id_counter = Counter.new


          BOAT_ID_NOCHECK = -1
          INVALID_BOAT_ID = 0

          def initialize()
            @object_id = Yacht.oid_counter.next()
            @boat_id = INVALID_BOAT_ID
          end

          def init_boat()
            @boat_id = Boat.boat_id_counter.next()
          end

          def check_timeout(duration)
            return false
          end
        end
      end
  end
end
