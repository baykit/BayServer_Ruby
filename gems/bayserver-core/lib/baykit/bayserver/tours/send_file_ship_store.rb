require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/lifecycle_listener'

require 'baykit/bayserver/tours/send_file_ship'

require 'baykit/bayserver/util/object_store'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Tours
        class SendFileShipStore < Baykit::BayServer::Util::ObjectStore
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent

          class AgentListener
            include Baykit::BayServer::Agent::LifecycleListener # implements

            def add(agt_id)
              SendFileShipStore.stores[agt_id] = SendFileShipStore.new()
            end

            def remove(agt_id)
              SendFileShipStore.stores.delete(agt_id)
            end
          end

          class << self
            attr :stores
          end
          @stores = {}

          def initialize()
            super
            @factory = -> { SendFileShip.new() }
          end

          def print_usage(indent)
            BayLog.info("%sSendFileShipStore Usage:", StringUtil.indent(indent))
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
