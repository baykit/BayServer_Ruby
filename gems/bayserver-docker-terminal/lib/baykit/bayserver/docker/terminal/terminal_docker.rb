require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/docker/base/port_base'
require 'baykit/bayserver/tours/content_consume_listener'

require 'baykit/bayserver/docker/terminal/fully_hijackers_yacht'
require 'baykit/bayserver/docker/terminal/terminal_train'

module Baykit
  module BayServer
    module Docker
      module Terminal
        class TerminalDocker < Baykit::BayServer::Docker::Base::ClubBase
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent::Transporter
          include Baykit::BayServer::Tours

          RACK_TERMINAL_PIPE = "rack.terminal.pipe"
          DEFAULT_POST_CACHE_THRESHOLD = 1024 * 128   # 128 KB
          RACK_ERR = "Cannot find rack package. If you want to use terminal docker, please install rack package like 'gem install rack'."

          RACK_MULTITHREAD     = 'rack.multithread'
          RACK_MULTIPROCESS    = 'rack.multiprocess'
          RACK_RUNONCE         = 'rack.run_once'
          RACK_HIJACK_IO       = 'rack.hijack_io'
          HTTP_VERSION         = 'HTTP_VERSION'

          attr_accessor :app
          attr :config
          attr :environment
          attr :post_cache_threshold
          attr :available

          def initialize
            @post_cache_threshold = DEFAULT_POST_CACHE_THRESHOLD
            @available = false
          end

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            super

            begin
              require 'rack'
            rescue LoadError => e
              BayLog.error(RACK_ERR)
              return
            end

            require 'rack/handler/bayserver'

            if Rack::Handler::BayServer.app != nil
              # rackup mode
              @app = Rack::Handler::BayServer.app
            else
              if !StringUtil.set?(@config)
                raise ConfigException.new(elm.file_name, elm.line_no, "Config not specified")
              elsif not ::File.exist?(@config)
                raise ConfigException.new(elm.file_name, elm.line_no, "Config not found: %s", @config)
              end
              if @environment == nil
                @environment = "deployment"
              end
              options = {
                :server => "terminal",
                :config => @config,
                :environment => @environment,
                :docker => self,
              }
              Rack::Server.start options
            end

            @available = true
          end

          ######################################################
          # Implements DockerBase
          ######################################################

          def init_key_val(kv)
            case kv.key.downcase
            when "config"
              @config = Baykit::BayServer::BayServer.parse_path(kv.value)
            when "environment"
              @environment = kv.value
            when "postcachethreshold"
              @post_cache_threshold = kv.value.to_i
            else
              return super
            end
            return true
          end

          ######################################################
          # Implements Club
          ######################################################

          def arrive(tur)

            if not @available
              tur.res.headers.set_content_type("text/plain")
              tur.res.set_consume_listener(&ContentConsumeListener::DEV_NULL)
              tur.res.send_headers(tur.id)
              tur.res.send_content(tur.id, RACK_ERR, 0, RACK_ERR.length)
              tur.res.end_content(tur.id)
              return
            end

            if tur.req.uri.include? ".."
              raise HttpException.new HttpStatus::FORBIDDEN, tur.req.uri
            end

            env = create_env tur
            train = TerminalTrain.new(self, tur, @app, env)
            train.start_tour()
          end

          def create_env(tur)
            env = {}

            cont_len = tur.req.headers.content_length()
            if cont_len > 0
              env["CONTENT_LENGTH"] = cont_len.to_s
            end
            cont_type = tur.req.headers.content_type()
            if StringUtil.set? cont_type
              env["CONTENT_TYPE"]      = cont_type
            end


            env["GATEWAY_INTERFACE"] = "CGI/1.1"
            #env[Rack::PATH_INFO] = tur.req.path_info == nil ? "" : tur.req.path_info
            pos = tur.req.uri.index('?')
            if pos and pos > 0
              env[Rack::PATH_INFO] = tur.req.uri[0 .. pos-1]
            else
              env[Rack::PATH_INFO] = tur.req.uri
            end
            env[Rack::QUERY_STRING] = tur.req.query_string == nil ? "" : tur.req.query_string
            env["REMOTE_ADDR"] = tur.req.remote_address
            env["REMOTE_HOST"] = tur.req.remote_address  # for performance reason
            env["REMOTE_USER"] = tur.req.remote_user == nil ? "" : tur.req.remote_user
            env[Rack::REQUEST_METHOD] = tur.req.method
            env["REQUEST_URI"]  = tur.req.uri
            #env[Rack::SCRIPT_NAME] = tur.req.script_name == nil ? "" : tur.req.script_name
            env[Rack::SCRIPT_NAME] = ""
            env[Rack::SERVER_NAME] = tur.req.server_name
            env[Rack::SERVER_PORT]  = tur.req.server_port.to_s
            env[Rack::SERVER_PROTOCOL] = tur.req.protocol
            env["SERVER_SOFTWARE"] = Baykit::BayServer::BayServer.get_software_name

            tur.req.headers.names.each do |name|
              tur.req.headers.values(name).each do |val|
                if /^content-type$/i =~ name || /^content-length$/i =~ name
                  next
                end
                name = "HTTP_" + name
                name.gsub!(/-/o, "_")
                name.upcase!
                env[name] = val
              end
            end

            env[Rack::RACK_VERSION] = Rack::VERSION
            env[Rack::RACK_ERRORS] = STDERR
            env[Rack::RACK_INPUT] = nil
            env[RACK_MULTITHREAD] = true
            env[RACK_MULTIPROCESS] = BayServer.harbor.multi_core?
            env[RACK_RUNONCE] = false
            env[Rack::RACK_URL_SCHEME] = tur.is_secure ? "https" : "http"
            env[Rack::RACK_IS_HIJACK] = true

            env[Rack::RACK_HIJACK] = lambda do
              pip = IO.pipe
              env[RACK_TERMINAL_PIPE] = pip

              w_pipe = pip[1]

              env[RACK_HIJACK_IO] = w_pipe

              yat = FullyHijackersYacht.new()
              bufsize = tur.ship.protocol_handler.max_res_packet_data_size()
              tp = PlainTransporter.new(false, bufsize)

              yat.init(tur, pip[0], tp)
              tp.init(tur.ship.agent.non_blocking_handler, pip[0], yat)
              tur.ship.resume(tur.ship_id)

              w_pipe
            end

            env[RACK_HIJACK_IO] = nil

            env[HTTP_VERSION] = tur.req.protocol
            env
          end
        end
      end
    end
  end
end
