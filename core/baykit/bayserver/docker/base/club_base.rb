require 'baykit/bayserver/docker/club'
require 'baykit/bayserver/docker/base/docker_base'
require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/util/class_util'

module Baykit
  module BayServer
    module Docker
      module Base
        class ClubBase < Baykit::BayServer::Docker::Base::DockerBase
          include Baykit::BayServer::Docker::Club # implements

          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util

          attr :file_name
          attr :extension
          attr :charset
          attr :locale
          attr :decode_path_info

          def initialize
            @file_name = nil
            @extension = nil
            @charset = nil
            @locale = nil
            @decode_path_info = true
          end

          def to_s()
            return ClassUtil.get_local_name(self.class)
          end
          
          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            super
            p = elm.arg.rindex('.');
            if(p == nil)
              @file_name = elm.arg
              @extension = nil
            else
              @file_name = elm.arg[0, p]
              @extension = elm.arg[p+1 .. -1]
            end

          end

          ######################################################
          # Implements DockerBase
          ######################################################

          def init_key_val(kv)
            case kv.key.downcase
            when "decodepathinfo"
              @decode_path_info = StringUtil.parse_bool(kv.value)
            when "charset"
              @charset = kv.value
            else
              return super
            end
            return true
          end

          ######################################################
          # Implements Club
          ######################################################

          def matches(fname)
            # check club
            pos = fname.index(".")
            if(pos == nil)
              # fname has no extension
              if(@extension != nil)
                return false
              end

              if(@file_name == "*")
                return true
              end

              return fname == @file_name
            else
              # fname has extension
              if(@extension == nil)
                return false
              end

              nm = fname[0, pos]
              ext = fname[pos + 1 .. -1]

              if(@extension != "*" && ext != @extension)
                return false
              end

              if(@file_name == "*")
                return true
              else
                return nm == @file_name
              end
            end
          end

          def to_s
            self.class.name
          end

          def inspect
            self.class.name
          end
        end
      end
    end
  end
end
