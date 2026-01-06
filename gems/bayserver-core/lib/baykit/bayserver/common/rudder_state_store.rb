require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/lifecycle_listener'

require 'baykit/bayserver/common/rudder_state'

require 'baykit/bayserver/util/object_store'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Common
      class RudderStateStore  < Baykit::BayServer::Util::ObjectStore
        include Baykit::BayServer::Util
        include Baykit::BayServer::Agent
        class AgentListener
          include Baykit::BayServer::Agent::LifecycleListener # implements

          def add(agt_id)
            RudderStateStore.stores[agt_id] = RudderStateStore.new();
          end

          def remove(agt_id)
            RudderStateStore.stores.delete(agt_id);
          end
        end

        class << self
          #  Agent id => InboundShipStore
          attr :stores
        end
        @stores = {}


        def initialize
          super
          @factory = -> { RudderState.new() }
        end

        #
        #  print memory usage
        #
        def print_usage(indent)
          BayLog.info("%sRudderStateStore Usage:", StringUtil.indent(indent))
          super(indent+1)
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

