require 'baykit/bayserver/bayserver'
require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/lifecycle_listener'
require 'baykit/bayserver/util/executor_service'
require 'baykit/bayserver/sink'

module Baykit
  module BayServer
    module Taxi
      class TaxiRunner
        include Baykit::BayServer
        include Baykit::BayServer::Agent
        include Baykit::BayServer::Util

        class AgentListener
          include Baykit::BayServer::Agent::LifecycleListener # implements

          def add(agt)
            TaxiRunner.runners[agt.agent_id - 1] = TaxiRunner.new(agt)
          end

          def remove(agt)
            BayLog.debug("%s Remove tax runner", agt)
            TaxiRunner.runners[agt.agent_id - 1].terminate()
            TaxiRunner.runners[agt.agent_id - 1] = nil
          end
        end


        # define class instance accessor
        class << self
          attr :max_taxis
          attr :runners
        end

        attr :agent
        attr :exe
        attr :running_taxis
        attr :lock

        def initialize(agt)
          @agent = agt
          @exe = ExecutorService.new("TaxiRunner", TaxiRunner.max_taxis)
          @agent.add_timer_handler(self)
          @running_taxis = []
          @lock = Monitor.new()
        end

        ######################################################
        # Implements TimerHandler
        ######################################################

        def on_timer()
          @lock.synchronize do
            @running_taxis.each do |txi|
              txi.on_timer()
            end
          end
        end

        ######################################################
        # Custom methods
        ######################################################

        def terminate()
          @agent.remove_timer_handler(self)
          @exe.shutdown
        end

        def submit(txi)
          @exe.submit() do
            if @agent.aborted
              BayLog.error("Agent is aborted")
              return
            end

            @lock.synchronize do
              @running_taxis << txi
            end

            begin
              txi.run()
            rescue => e
              BayLog.fatal_e(e)
              @agent.req_shutdown
            ensure
              @lock.synchronize do
                @running_taxis.delete(txi)
              end
            end
          end
        end

        ######################################################
        # Class methods
        ######################################################

        def TaxiRunner.init(max_taxis)
          if(max_taxis <= 0)
            raise Sink.new()
          end
          @max_taxis = max_taxis
          @runners = []
          GrandAgent.add_lifecycle_listener(AgentListener.new())
        end

        def TaxiRunner.post(agt_id, txi)
          BayLog.debug("agt#%d post taxi: thread=%s taxi=%s", agt_id, Thread.current.name, txi);
          begin
            @runners[agt_id - 1].submit(txi)
            return true
          rescue => e
            BayLog.error_e(e)
            return false
          end
        end
      end
    end
  end
end

