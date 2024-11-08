require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/lifecycle_listener'

require 'baykit/bayserver/common/inbound_ship'
require 'baykit/bayserver/common/inbound_ship_store'

require 'baykit/bayserver/util/object_store'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Common
        class InboundShipStore < Baykit::BayServer::Util::ObjectStore
          include Baykit::BayServer::WaterCraft
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent

          class AgentListener
            include Baykit::BayServer::Agent::LifecycleListener # implements

            def add(agt_id)
              InboundShipStore.stores[agt_id] = InboundShipStore.new();
            end

            def remove(agt_id)
              InboundShipStore.stores.delete(agt_id);
            end
          end

          class << self
            #  Agent id => InboundShipStore
            attr :stores
          end
          @stores = {}

          def initialize()
            super
            @factory = -> { InboundShip.new() }
          end

          #
          #  print memory usage
          #
          def print_usage(indent)
            BayLog.info("%sInboundShipStore Usage:", StringUtil.indent(indent));
            super(indent+1);
          end


          ######################################################
          # class methods
          ######################################################
          def self.init()
            GrandAgent.add_lifecycle_listener(AgentListener.new())
          end

          def self.get_store(agent_id)
            return @stores[agent_id]
          end

        end
    end
  end
end
