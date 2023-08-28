require 'baykit/bayserver/docker/base/reroute_base'

module Baykit
  module BayServer
    module Docker
      module WordPress
        class WordPressDocker < Baykit::BayServer::Docker::Base::RerouteBase
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent

          attr :town_path

          def init(elm, parent)
            super

            @town_path = parent.location
          end

          def reroute(twn, uri)

            uri_parts = uri.split("?")
            uri2 = uri_parts[0]
            if !match(uri2)
              return uri
            end

            rel_path = uri2[twn.name.length .. -1]
            if rel_path.start_with?("/")
                rel_path = rel_path[1 .. -1]
            end

            rel_parts = rel_path.split("/")
            check_path = ""

            rel_parts.each do | path_item |
              if StringUtil.set? check_path
                check_path += "/"
              end
              check_path += path_item

              if File.exist?("#{twn.location}/#{check_path}")
                return uri
              end
            end

            if !File.exist?("#{twn.location}/#{rel_path}")
              return "#{twn.name}index.php/#{uri[twn.name.length .. -1]}"
            else
              return uri
            end
          end
        end
      end
    end
  end
end