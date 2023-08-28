require 'baykit/bayserver/bayserver'
require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/protocol/protocol_handler_store'
require 'baykit/bayserver/protocol/packet_store'
require 'baykit/bayserver/tours/tour_store'
require 'baykit/bayserver/docker/base/inbound_ship_store'
require 'baykit/bayserver/docker/warp/warp_docker'

require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    class MemUsage
      include Baykit::BayServer
      include Baykit::BayServer::Agent
      include Baykit::BayServer::Protocol
      include Baykit::BayServer::Tours
      include Baykit::BayServer::Docker::Warp
      include Baykit::BayServer::Docker::Base
      include Baykit::BayServer::Util

      class AgentListener
        include Baykit::BayServer::Agent::GrandAgent::GrandAgentLifecycleListener

        def add(agt)
          MemUsage.mem_usages[agt.agent_id] = MemUsage.new(agt.agent_id);
        end

        def remove(agt)
          MemUsage.mem_usages.delete(agt.agent_id)
        end
      end

      class << self
        attr :mem_usages
      end
      # Agent ID => MemUsage
      @mem_usages = {}

      attr :agent_id

      def initialize(agt_id)
        @agent_id = agt_id
      end

      def print_usage(indent)
        InboundShipStore.get_store(@agent_id).print_usage(indent+1)
        ProtocolHandlerStore.get_stores(@agent_id).each do |store|
          store.print_usage(indent+1)
        end
        PacketStore.get_stores(@agent_id).each do |store|
          store.print_usage(indent+1)
        end
        TourStore.get_store(@agent_id).print_usage(indent+1);
        BayServer.cities.cities.each do |city|
          print_city_usage(nil, city, indent)
        end

        BayServer.ports.each do |port|
          port.cities.cities().each do |city|
            print_city_usage(port, city, indent)
          end
        end
      end


      def print_city_usage(port, city, indent)
        if port == nil
          pname = ""
        else
          pname = "@#{port}"
        end

        city.clubs().each do |club|
          if club.kind_of?(WarpDocker)
            BayLog.info("%sClub(%s%s) Usage:", StringUtil.indent(indent), club, pname);
            club.get_ship_store(@agent_id).print_usage(indent+1)
          end
        end
        city.towns().each do |town|
          town.clubs().each do |club|
            if club.kind_of?(WarpDocker)
              BayLog.info("%sClub(%s%s) Usage:", StringUtil.indent(indent), club, pname);
              club.get_ship_store(@agent_id).print_usage(indent+1)
            end
          end
        end
      end


      ######################################################
      # Class methods
      ######################################################
      def self.init()
        GrandAgent.add_lifecycle_listener(AgentListener.new());
      end

      def self.get(agent_id)
        return @mem_usages[agent_id]
      end

    end
  end
end
