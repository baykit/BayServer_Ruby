module Baykit
  module BayServer
    module Docker
      module Fcgi
        module FcgDocker
          include Baykit::BayServer::Docker::Docker  # implements

          PROTO_NAME = "fcgi"
        end
      end
    end
  end
end

