require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/lifecycle_listener'
require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Tours
      #
      # TourStore
      #   You must lock object before call methods because all the methods may be called by different threads. (agent, tours agent)
      #
      class TourStore
        include Baykit::BayServer::Agent
        include Baykit::BayServer::Util


        class AgentListener
          include Baykit::BayServer::Agent::LifecycleListener  # implements

          def add(agt)
            TourStore.stores[agt.agent_id] = TourStore.new();
          end

          def remove(agt)
            TourStore.stores.delete(agt.agent_id);
          end
        end


        MAX_TOURS = 1024

        attr :free_tours
        attr :active_tour_map

        # class variables
        class << self
          attr :max_count

          # Agent ID => TourStore
          attr :stores
        end
        @stores = {}


        def initialize()
          @free_tours = []
          @active_tour_map = {}
          @lock = Monitor.new
        end

        def get(key)
          @lock.synchronize do
            return @active_tour_map[key]
          end
        end

        def rent(key, ship, force = false)
          @lock.synchronize do
            tur = get(key)
            if tur != nil
              raise Sink.new("#{ship} Tour already exists")
            end

            if !@free_tours.empty?
              tur = @free_tours.delete_at(@free_tours.length - 1)
            else
              if !force && (@active_tour_map.length >= TourStore.max_count)
                BayLog.warn("Max tour count reached")
                return nil
              else
                tur = Tour.new()
              end
            end

            @active_tour_map[key] = tur
            return tur
          end
        end

        def Return(key)
          @lock.synchronize do
            if !@active_tour_map.key?(key)
              raise Sink.new("Tour is not active: key=#{key}")
            end

            tur = @active_tour_map.delete(key)
            tur.reset()
            @free_tours.append(tur)
          end
        end

        #
        # print memory usage
        #
        def print_usage(indent)
          BayLog.info("%sTour store usage:", StringUtil.indent(indent))
          BayLog.info("%sfreeList: %d", StringUtil.indent(indent+1), @free_tours.length())
          BayLog.info("%sactiveList: %d", StringUtil.indent(indent+1), @active_tour_map.length())
          if BayLog.debug_mode?
            @active_tour_map.values.each do |obj|
              BayLog.debug("%s%s", StringUtil.indent(indent+1), obj)
            end
          end
        end


        ######################################################
        # class methods
        ######################################################
        def self.init(max_tours)
          @max_count = max_tours
          GrandAgent.add_lifecycle_listener(AgentListener.new())
        end

        def self.get_store(agent_id)
          return stores[agent_id]
        end
      end
    end
  end
end

