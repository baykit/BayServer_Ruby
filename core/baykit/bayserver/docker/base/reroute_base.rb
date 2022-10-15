require 'baykit/bayserver/docker/base/docker_base'

module Baykit
  module BayServer
    module Docker
      module Base
        class RerouteBase < Baykit::BayServer::Docker::Base::DockerBase
          include Reroute # implements

          include Baykit::BayServer::Bcf

          def init(elm, parent)
            name = elm.arg;
            if name != "*"
              raise ConfigException.new(elm.file_name, elm.line_no, "Invalid reroute name: %s", name)
            end
            super
          end


          def match(uri)
            return true
          end
        end
      end
    end
  end
end
