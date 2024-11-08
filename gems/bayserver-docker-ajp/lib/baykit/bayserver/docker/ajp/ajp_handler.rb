
module Baykit
  module BayServer
    module Docker
      module Ajp
        module AjpHandler  # interface
          def on_protocol_error(e)
            raise NotImplementedError.new
          end
        end
      end
    end
  end
end
