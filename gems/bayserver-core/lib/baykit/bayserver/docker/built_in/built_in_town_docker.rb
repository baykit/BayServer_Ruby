require 'baykit/bayserver/docker/club'
require 'baykit/bayserver/docker/town'
require 'baykit/bayserver/docker/reroute'
require 'baykit/bayserver/docker/permission'
require 'baykit/bayserver/docker/base/docker_base'

module Baykit
  module BayServer
    module Docker
      module BuiltIn
        class BuiltInTownDocker < Baykit::BayServer::Docker::Base::DockerBase
          include Baykit::BayServer::Docker::Town #implements

          include Baykit::BayServer::Docker
          include Baykit::BayServer::Bcf

          attr :name
          attr :location
          attr :welcome
          attr :clubs
          attr :permission_list
          attr :city
          attr :reroute_list

          def initialize
            @name = nil
            @location = nil
            @welcome = nil
            @clubs = []
            @permission_list = []
            @city = nil
            @reroute_list = []
          end

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            arg = elm.arg
            if !arg.start_with? "/"
              arg = "/" + arg
            end

            @name = arg
            if !@name.end_with? "/"
              @name = @name + "/"
            end

            @city = parent
            super
          end

          def init_docker(dkr)
            if dkr.kind_of?(Baykit::BayServer::Docker::Club)
              @clubs.append(dkr)
            elsif dkr.kind_of?(Baykit::BayServer::Docker::Permission)
              @permission_list.append(dkr)
            elsif dkr.kind_of?(Baykit::BayServer::Docker::Reroute)
              @reroute_list.append(dkr)
            else
              return super
            end
            return true
          end

          def init_key_val(kv)
            case kv.key.downcase
            when "location"
              @location = kv.value
              if !File.absolute_path?(@location)
                @location = BayServer.get_location(@location)
                if !File.directory?(@location)
                  raise ConfigException.new(kv.file_name, kv.line_no, BayMessage.get(:CFG_INVALID_LOCATION, kv.value))
                end
              end
            when "index"
              @welcome = kv.value
            when "welcome"
              @welcome = kv.value
            else
              return super
            end
            return true;
          end

          ######################################################
          # Implements Town
          ######################################################

          def reroute(uri)
            @reroute_list.each do |r|
              uri = r.reroute(self, uri)
            end
            return uri
          end

          def matches(uri)
            if uri.start_with?(@name)
              return MATCH_TYPE_MATCHED
            elsif uri + "/" == name
              return MATCH_TYPE_CLOSE
            else
              return MATCH_TYPE_NOT_MATCHED
            end
          end

          def tour_admitted(tur)
            @permission_list.each do |p|
              p.tour_admitted(tur)
            end
          end
        end
      end
    end
  end
end
