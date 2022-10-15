require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/docker/cgi/cgi_docker'

module Baykit
  module BayServer
    module Docker
      module Cgi
        class PhpCgiDocker < Baykit::BayServer::Docker::Cgi::CgiDocker
          include Baykit::BayServer::Util

          ENV_PHP_SELF = "PHP_SELF"
          ENV_REDIRECT_STATUS = "REDIRECT_STATUS"

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            super

            if @interpreter == nil
              @interpreter = "php-cgi";
            end

            BayLog.debug("PHP interpreter: " + interpreter)
          end

          ######################################################
          # Override CgiDocker
          ######################################################

          def create_command(env)
            env[ENV_PHP_SELF] = env[CgiUtil::SCRIPT_NAME]
            env[ENV_REDIRECT_STATUS] = 200.to_s
            super
          end
        end
      end
    end
  end
end