require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/lifecycle_listener'
require 'baykit/bayserver/util/object_store'
require 'baykit/bayserver/protocol/packet_factory'

module Baykit
  module BayServer
    module Protocol
      class PacketStore
        include Baykit::BayServer::Util::Reusable # implements

        include Baykit::BayServer::Agent
        include Baykit::BayServer::Util

        class AgentListener
          include Baykit::BayServer::Agent::LifecycleListener # implements

          def add(agt)
            PacketStore.proto_map.values().each do |ifo|
             ifo.add_agent(agt.agent_id);
            end
          end

          def remove(agt)
            PacketStore.proto_map.values().each do |ifo|
              ifo.remove_agent(agt.agent_id);
            end
          end
        end


        class ProtocolInfo
          attr :protocol
          attr :packet_factory

          # Agent ID => PacketStore
          attr :stores

          def initialize(proto, pkt_factory)
            @protocol = proto
            @packet_factory = pkt_factory
            @stores = {}
          end

          def add_agent(agt_id)
            store = PacketStore.new(@protocol, @packet_factory);
            @stores[agt_id] = store;
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
        attr :store_map
        attr :factory

        def initialize(proto, factory)
          @protocol = proto
          @factory = factory
          @store_map = {}
        end

        def reset
          @store_map.values.each do |store|
            store.reset
          end
        end

        def rent(type)
          if type == nil
            raise RuntimeError.new("Nil argument")
          end

          store = @store_map[type]
          if store == nil
            store = ObjectStore.new(lambda do
              if @factory.kind_of?(PacketFactory)
                return @factory.create_packet(type)
              else
                # lambda
                return @factory.call(type)
              end
            end)
            @store_map[type] = store
          end
          return store.rent
        end

        def Return(pkt)
          store = @store_map[pkt.type]
          #puts "Return packet #{pkt}"
          store.Return(pkt)
        end


        def print_usage(indent)
          BayLog.info("%sPacketStore(%s) usage nTypes=%d", StringUtil.indent(indent), @protocol, @store_map.keys().size)
          @store_map.keys.each do |type|
            BayLog.info("%sType: %s", StringUtil.indent(indent+1), type)
            @store_map[type].print_usage(indent+2)
          end
        end

        ######################################################
        # class methods
        ######################################################
        def self.init()
          GrandAgent.add_lifecycle_listener(AgentListener.new())
        end

        def self.get_store(protocol, agent_id)
          return @proto_map[protocol].stores[agent_id]
        end

        def self.register_protocol(protocol, factory)
          if !@proto_map.include?(protocol)
            @proto_map[protocol] = PacketStore::ProtocolInfo.new(protocol, factory)
          end
        end

        def self.get_stores(agent_id)
          store_list = []
          @proto_map.values.each do |ifo|
            store_list.append(ifo.stores[agent_id])
          end
          return store_list
        end
      end
    end
  end
end

