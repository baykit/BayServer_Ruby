require 'baykit/bayserver/agent/transporter/package'
require 'baykit/bayserver/docker/base/port_base'
require 'baykit/bayserver/docker/http/h1/package'


module Baykit
  module BayServer
    module Docker
      module Http
        module HtpDocker
          #
          # interface
          #

          H1_PROTO_NAME = "h1"
          H2_PROTO_NAME = "h2"
        end
      end
    end
  end
end

