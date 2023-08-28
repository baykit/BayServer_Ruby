require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer

    class BayDockers
      include Bcf
      include Util

      attr :docker_map

      def initialize()
        @docker_map = {}
      end

      def init(conf)
        p = BcfParser.new()
        doc = p.parse(conf)
        #doc.print_document

        doc.content_list.each do |obj|
          if(obj.instance_of?(BcfKeyVal))
            @docker_map[obj.key] = obj.value
          end
        end
      end

      def create_docker(elm, parent)
        alias_name = elm.get_value("docker")
        d = create_docker_by_alias(elm.name, alias_name)
        d.init(elm, parent)
        d
      end

      def create_docker_by_alias(category, alias_name)

        if StringUtil.empty?(alias_name)
          key = category
        else
          key = category + ":" + alias_name
        end

        cls = @docker_map[key]
        if cls == nil
          raise BayException.new(BayMessage.get(:CFG_DOCKER_NOT_FOUND, key))
        end

        require_file = cls.gsub(/::/, "/").gsub(/([a-z])([A-Z])/, "\\1_\\2").downcase.gsub('bay_server', 'bayserver').gsub('/docker/default_', '/docker/default')
        require require_file

        begin
          return Object.const_get(cls).new()
        rescue => e
          raise e
        end
      end
    end
  end
end
