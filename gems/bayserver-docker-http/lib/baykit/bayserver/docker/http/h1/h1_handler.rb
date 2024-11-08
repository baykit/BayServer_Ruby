
module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          module H1Handler  # interface
            def on_protocol_error(e)
              raise NotImplementedError.new
            end
          end
        end
      end
    end
  end
end
