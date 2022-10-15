require 'baykit/bayserver/bcf/package'

module Baykit
  module BayServer
    module Util
      class Mimes
        include Baykit::BayServer::Bcf

        @@mime_map = {}

        def self.init(bcf_file)
          p = BcfParser.new()
          doc = p.parse(bcf_file)
          doc.content_list.each do |kv|
            if kv.instance_of? BcfKeyVal
              @@mime_map[kv.key] = kv.value
            end
          end
        end

        def self.type(ext)
          @@mime_map[ext.downcase]
        end
      end
    end
  end
end
