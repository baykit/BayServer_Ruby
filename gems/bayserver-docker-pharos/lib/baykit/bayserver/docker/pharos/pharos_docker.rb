require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/config_exception'
require 'baykit/bayserver/http_exception'
require 'baykit/bayserver/docker/base/club_base'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/url_decoder'
require 'baykit/bayserver/docker/pharos/pharos_runtime'
require 'baykit/bayserver/docker/pharos/pharos_content_handler'

module Baykit
  module BayServer
    module Docker
      module Pharos

        # BayServer docker that runs PHP via libphp.so embedded in the
        # BayServer process (= same lifecycle as php-fpm, but in-process
        # and without the FCGI envelope or fork+exec overhead).
        #
        # Plan usage:
        #   [club *.php]
        #       docker pharos
        #       libPhpPath /path/to/libphp.so   # required, ZTS embed build
        #
        # The runtime is initialised once per process (shared across all
        # grand agents in this BayServer instance). Re-initialising libphp
        # would conflict with PHP's "single SAPI per process" assumption.
        class PharosDocker < Baykit::BayServer::Docker::Base::ClubBase
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Docker

          RUNTIME_MU = Mutex.new

          @runtime = nil
          class << self
            attr_accessor :runtime
          end

          def initialize
            super
            @lib_php_path = nil
            @ini_path     = nil
          end

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            super

            if StringUtil.empty?(@lib_php_path)
              raise ConfigException.new(elm.file_name, elm.line_no,
                "PharosDocker requires 'libPhpPath' " \
                "(/path/to/libphp.so, ZTS embed build)")
            end

            # Initialise runtime once per process. Plan parse is
            # single-threaded in practice, but guard cheaply with a mutex.
            RUNTIME_MU.synchronize do
              if PharosDocker.runtime.nil?
                rt = PharosRuntime.new(@lib_php_path)
                rt.init
                PharosDocker.runtime = rt
              end
            end

            BayLog.info("PharosDocker ready: libPhpPath=%s ini=%s",
                        @lib_php_path, @ini_path)
          end

          ######################################################
          # Implements DockerBase
          ######################################################

          def init_key_val(kv)
            case kv.key.downcase
            when "libphppath"
              @lib_php_path = kv.value
            when "inipath"
              @ini_path = kv.value
            else
              return super
            end
            true
          end

          ######################################################
          # Implements Club
          ######################################################

          def arrive(tur)
            # Resolve the .php file path the same way FileDocker does:
            # docroot + (uri minus town prefix), URL-decoded, query-stripped.
            rel_path = tur.req.rewritten_uri || tur.req.uri
            unless StringUtil.empty?(tur.town.name)
              rel_path = rel_path[tur.town.name.length..]
            end
            q = rel_path.index('?')
            rel_path = rel_path[0, q] if q

            begin
              rel_path = URLDecoder.decode(rel_path, tur.req.charset)
            rescue => e
              BayLog.error("Cannot decode path: %s: %s", rel_path, e)
            end

            file = File.join(tur.town.location, rel_path)
            unless File.file?(file)
              raise HttpException.new(HttpStatus::NOT_FOUND, file)
            end

            rt = PharosDocker.runtime
            if rt.nil?
              raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR,
                "PharosRuntime not initialised")
            end

            handler = PharosContentHandler.new(tur, file, rt)
            tur.req.set_content_handler(handler)
          end
        end
      end
    end
  end
end
