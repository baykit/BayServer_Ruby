require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/tours/package'
require 'baykit/bayserver/docker/base/club_base'
require 'baykit/bayserver/docker/send_file/file_content_handler'
require 'baykit/bayserver/docker/send_file/directory_train'

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
              pos = rel_path.index('?')
              if pos != nil
                rel_path = rel_path[0, pos]
              end

              begin
                rel_path = URLDecoder.decode(rel_path, tur.req.charset)
              rescue Encoding::UndefinedConversionError => e
                BayLog.error_e(e, "%s Cannot decode request path: %s", tur, rel_path)
              end

              real = "#{tur.town.location}/#{rel_path}"

              if File.directory?(real) && @list_files
                train = DirectoryTrain.new(tur, real)
                train.start_tour()
              else
                handler = FileContentHandler.new(real)
                tur.req.set_content_handler(handler)
              end

            end

          end
        end
      end
    end
  end
end
