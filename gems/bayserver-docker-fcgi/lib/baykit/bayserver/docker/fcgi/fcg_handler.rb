
module Baykit
  module BayServer
    module Docker
      module Fcgi
        module FcgHandler  # interface
          def on_protocol_error(e)
            raise NotImplementedError.new
          end
        end
      end
    end
  end
end
