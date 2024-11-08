require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/lifecycle_listener'
require 'baykit/bayserver/util/object_store'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Protocol
      class ProtocolHandlerStore < Baykit::BayServer::Util::ObjectStore
        include Baykit::BayServer::Agent
        include Baykit::BayServer::Util

        class AgentListener
          include Baykit::BayServer::Agent::LifecycleListener # implements

          def add(agt)
            ProtocolHandlerStore.proto_map.values().each {|ifo| ifo.add_agent(agt) }
          end

          def remove(agt)
            ProtocolHandlerStore.proto_map.values().each { |ifo| ifo.remove_agent(agt) }
          end
        end


        class ProtocolInfo
          attr :protocol
          attr :server_mode
          attr :protocol_handler_factory
          attr :stores

          def initialize(proto, svr_mode, proto_hnd_factory)
            @protocol = proto
            @server_mode = svr_mode
            @protocol_handler_factory = proto_hnd_factory

            # Agent ID => ProtocolHandlerStore
            @stores = {}
          end

          def add_agent(agt_id)
            store = PacketStore.get_store(@protocol, agt_id);
            @stores[agt_id] = ProtocolHandlerStore.new(@protocol, @server_mode, @protocol_handler_factory, store);
          end

          def remove_agent(agt_id)
            @stores.delete(agt_id);
          end

        end

        class << self
          attr :proto_map
        end
        @proto_map = {}


        attr :protocol
        attr :server_mode

        def initialize(proto, svr_mode, proto_hnd_factory, pkt_store)
          super()
          @protocol = proto
          @server_mode = svr_mode
          @factory = -> do
            return proto_hnd_factory.create_protocol_handler(pkt_store)
          end
        end

        def print_usage(indent)
          BayLog.info("%sProtocolHandlerStore(%s%s) Usage:", StringUtil.indent(indent), @protocol, @server_mode ? "s" : "c")
          super(indent+1)
        end

        ######################################################
        # class methods
        ######################################################
        def self.init()
          GrandAgent.add_lifecycle_listener(AgentListener.new())
        end

        def self.get_store(protocol, svr_mode, agent_id)
          return @proto_map[construct_protocol(protocol, svr_mode)].stores[agent_id]
        end

        def self.get_stores(agent_id)
          store_list = []
          @proto_map.values.each do |ifo|
            store_list.append(ifo.stores[agent_id])
          end
          return store_list
        end

        def self.register_protocol(protocol, svr_mode, proto_hnd_factory)
          if !@proto_map.include?(construct_protocol(protocol, svr_mode))
            @proto_map[construct_protocol(protocol, svr_mode)] = ProtocolInfo.new(protocol, svr_mode, proto_hnd_factory)
          end
        end

        def self.construct_protocol(protocol, svr_mode)
          if(svr_mode)
            return protocol + "-s"
          else
            return protocol + "-c"
          end
        end
      end
    end
  end
end