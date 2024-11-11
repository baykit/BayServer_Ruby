require 'baykit/bayserver/bayserver'
require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/timer_handler'
require 'baykit/bayserver/agent/lifecycle_listener'
require 'baykit/bayserver/util/executor_service'
require 'baykit/bayserver/sink'

module Baykit
  module BayServer
    module Common
      class VehicleRunner

        class AgentListener
          include Baykit::BayServer::Agent::LifecycleListener # implements
          include Baykit::BayServer::Agent

          attr :runner
          def initialize(runner)
            @runner = runner
          end

          def add(agt_id)
            while @runner.services.length < agt_id
              @runner.services << nil
            end
            @runner.services[agt_id - 1] = VehicleRunner::VehicleService.new(GrandAgent.get(agt_id), @runner)
          end

          def remove(agt_id)
            BayLog.debug("agt#%d remove VehicleRunner", agt_id)
            @runner.services[agt_id - 1].terminate
            @runner.services[agt_id - 1] = nil
          end
        end


        class VehicleService
          include Baykit::BayServer::Util

          attr :agent
          attr :exe
          attr :runnings
          attr :runnings_lock

          def initialize(agt, runner)
            @agent = agt
            @agent.add_timer_handler(self)
            @runnings = []
            @runnings_lock = Mutex.new
            @exe = ExecutorService.new("Runner", runner.max_vehicles)
          end

          ########################################
          # Implements TimerHandler
          ########################################
          def on_timer
            @runnings_lock.synchronize do
              @runnings.each do |vcl|
                vcl.on_timer
              end
            end
          end


          ########################################
          # Private methods
          ########################################

          def terminate()
            @agent.remove_timer_handler(self)
            @exe.shutdown
          end

          def submit(vcl)
            @exe.submit() do
              if @agent.aborted
                BayLog.error("%s Agent is aborted", @agent)
                return
              end

              @runnings_lock.synchronize do
                @runnings << vcl
              end

              begin
                vcl.run
              rescue => e
                BayLog.fatal_e(e)
                @agent.req_shutdown
              ensure
                @runnings_lock.synchronize do
                  @runnings.delete(vcl)
                end
              end
            end
          end
        end

        include Baykit::BayServer::Agent

        attr :max_vehicles
        attr :services

        def initialize
          @max_vehicles = 0
          @services = []
        end

        ########################################
        # Custom methods
        ########################################
        def init(max)
          if(max <= 0)
            raise Sink.new()
          end
          @max_vehicles = max
          GrandAgent.add_lifecycle_listener(AgentListener.new(self))
        end

        def post(agt_id, vcl)
          @services[agt_id - 1].submit(vcl)
        end

      end
    end
  end
end
