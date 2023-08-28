require 'baykit/bayserver/agent/transporter/transporter'
require 'baykit/bayserver/agent/transporter/data_listener'
require 'baykit/bayserver/util/reusable'
require 'baykit/bayserver/util/counter'

module Baykit
  module BayServer
      module WaterCraft
        class Yacht
          include Baykit::BayServer::Agent::Transporter::DataListener # implements
          include Baykit::BayServer::Util::Reusable  # implements

          include Baykit::BayServer::Util


          # class variables
          class << self
            attr :oid_counter
            attr :yacht_id_counter
          end
          @oid_counter = Counter.new
          @yacht_id_counter = Counter.new


          attr :object_id
          attr :yacht_id

          YACHT_ID_NOCHECK = -1
          INVALID_YACHT_ID = 0

          def initialize()
            @object_id = Yacht.oid_counter.next()
            @yacht_id = INVALID_YACHT_ID
          end

          def init_yacht()
            @yacht_id = Yacht.yacht_id_counter.next()
          end
        end
      end
  end
end
