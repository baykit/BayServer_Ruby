
module Baykit
  module BayServer
    module Agent
      module Multiplexer
        class JobMultiplexerBase < MultiplexerBase
          include TimerHandler

          attr :anchorable
          attr :pipe

          def initialize(agt, anchorable)
            super(agt)

            @anchorable = anchorable
            @agent.add_timer_handler(self)

            @pipe = IO::pipe
          end

          #########################################
          # Implements Multiplexer
          #########################################

          def shutdown()
            close_all()
          end

          def on_busy()
            BayLog.debug("%s onBusy (ignore)", self)
          end

          def on_free()
            BayLog.debug("%s onFree", self)
            if @agent.aborted
              return
            end

            if @anchorable
              BayServer::anchorable_port_map.keys.each do |rd|
                req_accept(rd)
              end
            end
          end

          #########################################
          # Implements TimerHandler
          #########################################

          def on_timer()
            close_timeout_sockets()
          end
        end
      end
    end
  end
end