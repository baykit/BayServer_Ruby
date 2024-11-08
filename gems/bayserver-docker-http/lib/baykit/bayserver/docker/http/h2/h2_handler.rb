module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module H2Handler  # interface
            def on_protocol_error(e)
              raise NotImplementedError.new
            end
          end
        end
      end
    end
  end
end
