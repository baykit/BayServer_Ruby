require 'baykit/bayserver/util/class_util'

module Baykit
  module BayServer
    module Docker
      module Base
        class DockerBase
          include Baykit::BayServer::Docker::Docker # implements
          include Baykit::BayServer::Bcf

          include Baykit::BayServer::Util

          attr :type

          def to_s()
            return ClassUtil.get_local_name(self.class)
          end

          def init(elm, parent)
            @type = elm.name
            elm.content_list.each do |o|
              if o.kind_of? BcfKeyVal
                begin
                  if !init_key_val(o)
                    raise ConfigException.new o.file_name, o.line_no, BayMessage.get(:CFG_INVALID_PARAMETER, o.key)
                  end
                rescue ConfigException => e
                  raise e
                rescue => e
                  BayLog.error_e(e)
                  raise ConfigException.new o.file_name, o.line_no, BayMessage.get(:CFG_INVALID_PARAMETER_VALUE, o.key)
                end
              else
                begin
                  dkr = BayServer.dockers.create_docker(o, self)
                rescue ConfigException => e
                  raise e
                rescue => e
                  BayLog.error_e e
                  raise ConfigException.new(o.file_name, o.line_no, BayMessage.get(:CFG_INVALID_DOCKER, o.name))
                end

                if(!init_docker(dkr))
                  raise ConfigException.new(o.file_name, o.line_no, BayMessage.get(:CFG_INVALID_DOCKER, o.name))
                end
              end
            end
          end

          def init_docker(dkr)
            return false;
          end

          def init_key_val(kv)
            case kv.key.downcase
            when "docker"
              return true
            else
              return false
            end
          end
        end
      end
    end
  end
end
