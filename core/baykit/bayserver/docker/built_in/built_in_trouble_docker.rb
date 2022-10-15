require 'ipaddr'

require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/docker/trouble'


module Baykit
  module BayServer
    module Docker
      module BuiltIn
        class BuiltInTroubleDocker < Baykit::BayServer::Docker::Base::DockerBase
          include Trouble # import

          include Baykit::BayServer
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util

          attr :cmd_map

          def initialize
            @cmd_map = {}
          end

          def init_key_val(kv)
            status = Integer(kv.key)

            pos = kv.value.index(' ')
            if(pos == nil)
              raise ConfigException.new(kv.file_name, kv.line_no, BayMessage.get(:CFG_INVALID_PARAMETER, kv.key))
            end

            mstr = kv.value[0, pos]
            method = nil
            if(mstr.casecmp?("guide"))
              method = Method::GUIDE
            elsif(mstr.casecmp?("text"))
              method = Method::TEXT;
            elsif(mstr.casecmp?("reroute"))
              method = Method::REROUTE;
            else
              raise ConfigException.new(kv.file_name, kv.line_no, BayMessage.get(:CFG_INVALID_PARAMETER, kv.key))
            end

            @cmd_map[status] = Command.new(method, kv.value[pos + 1 .. -1])
            return true;
          end
        end

        def find(status)
          @cmd_map[status]
        end

      end
    end
  end
end

