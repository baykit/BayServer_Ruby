require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/lifecycle_listener'

require 'baykit/bayserver/docker/base/inbound_ship'
require 'baykit/bayserver/docker/base/inbound_ship_store'

require 'baykit/bayserver/util/object_store'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Docker
      module Base
        class InboundShipStore < Baykit::BayServer::Util::ObjectStore
          include Baykit::BayServer::WaterCraft
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent

          class AgentListener
            include Baykit::BayServer::Agent::LifecycleListener # implements

            def add(agt)
              InboundShipStore.stores[agt.agent_id] = InboundShipStore.new();
            end

            def remove(agt)
              InboundShipStore.stores.delete(agt.agent_id);
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
end
