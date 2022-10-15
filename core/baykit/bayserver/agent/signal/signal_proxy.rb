module Baykit
  module BayServer
    module Agent
      module Signal
        class SignalProxy

          def SignalProxy.register(sig, &handler)
            begin
              ::Signal.trap(sig, proc {handler.call()})
            rescue ArgumentError => e
              BayLog.warn(BayMessage.get(:INT_CANNOT_SET_SIG_HANDLER, e.message, sig))
            end
          end
        end
      end
    end
  end
end
