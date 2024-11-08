require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Secure
        include Docker   # implements

        def set_app_protocols(protocols)
          raise NotImplementedError.new
        end

        def reload_cert
          raise NotImplementedError.new
        end

        def new_transporter(agt_id, sip)
          raise NotImplementedError
        end
      end
    end
  end
end

