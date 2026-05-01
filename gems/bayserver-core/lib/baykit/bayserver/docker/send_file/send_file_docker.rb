require 'cgi'
require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/tours/package'
require 'baykit/bayserver/docker/base/club_base'
require 'baykit/bayserver/docker/send_file/file_content_handler'

require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Docker
      module SendFile
        class SendFileDocker < Baykit::BayServer::Docker::Base::ClubBase
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Tours

          attr :list_files

          ######################################################
          # Implements DockerBase
          ######################################################

          def init(elm, parent)
            super
          end

          def init_key_val(kv)
            case kv.key.downcase
            when "listfiles"
              @list_files = StringUtil.parse_bool(kv.value)
            else
              return super
            end
            return true
          end

          def arrive(tur)
            rel_path = tur.req.rewritten_uri != nil ? tur.req.rewritten_uri : tur.req.uri
            if StringUtil.set?(tur.town.name)
              rel_path = rel_path[tur.town.name.length .. -1]
            end

            pos = rel_path.index('?')
            if pos != nil
              rel_path = rel_path[0, pos]
            end

            begin
              rel_path = CGI.unescape(rel_path)
            rescue Encoding::CompatibilityError => e
              BayLog.error("Cannot decode path: %s: %s", rel_path, e)
            end

            real = File.join(tur.town.location, rel_path)

            handler = FileContentHandler.new(tur, real, tur.res.charset, @list_files)
            tur.req.set_content_handler(handler)
          end
        end
      end
    end
  end
end
