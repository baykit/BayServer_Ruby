require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/docker/base/port_base'
require 'baykit/bayserver/tours/content_consume_listener'
require 'baykit/bayserver/common/rudder_state_store'

require 'baykit/bayserver/docker/terminal/fully_hijackers_ship'
require 'baykit/bayserver/docker/terminal/terminal_train'

module Baykit
  module BayServer
    module Docker
      module Terminal
        class TerminalDocker < Baykit::BayServer::Docker::Base::ClubBase
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Agent::Multiplexer
          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Common

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
              # Application is already established on rackup mode
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
                server: "terminal",        # Server/handler name (used by rack or rackup)
                config: @config,           # Path to config.ru
                environment: @environment, # Rack environment (development, production, etc.)
                docker: self,              # Custom option passed to the server
              }

              # Rack 3.x moved Server/Handler to the `rackup` gem.
              begin
                require "rackup"           # Rack 3.x (or environments with rackup installed)
                require "rackup/handler/terminal"
                use_rackup = true
              rescue LoadError
                require "rack"
                require "rack/server"     # Rack 2.x
                use_rackup = false
              end

              if !use_rackup
                # Rack 2.x: start server via Rack::Server
                Rack::Server.start(options)
              else
                # Rack 3.x: start server via rackup

                opts = options.dup

                # Extract server/handler name (e.g. "puma", "webrick", "bayserver")
                server_name = opts.delete(:server) || 'bayserver'

                # Extract config.ru path
                config_file = opts.delete(:config)

                # Load Rack application and options from config.ru
                app, config_opts = Rack::Builder.parse_file(config_file)
                if config_opts == nil
                  config_opts = {}
                end

                # Merge options from config.ru with runtime options
                opts = config_opts.merge(opts)

                # Set default port if not specified
                opts[:Port] ||= 9292

                # Resolve handler via rackup
                handler =Rackup::Handler.get(server_name.to_s)

                # Run the Rack application using the selected handler
                handler.run(app, **opts)
              end
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
              tur.res.send_res_content(tur.id, RACK_ERR, 0, RACK_ERR.length)
              tur.res.end_res_content(tur.id)
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
            env[RACK_MULTIPROCESS] = BayServer.harbor.multi_core
            env[RACK_RUNONCE] = false
            env[Rack::RACK_URL_SCHEME] = tur.is_secure ? "https" : "http"
            env[Rack::RACK_IS_HIJACK] = true

            env[Rack::RACK_HIJACK] = lambda do
              pip = IO.pipe
              env[RACK_TERMINAL_PIPE] = pip

              w_pipe = pip[1]

              env[RACK_HIJACK_IO] = w_pipe

              agt = GrandAgent.get(tur.ship.agent_id)
              mpx = agt.net_multiplexer
              rd_read = IORudder.new(pip[0])
              sip = FullyHijackersShip.new()
              bufsize = tur.ship.protocol_handler.max_res_packet_data_size()

              tp = PlainTransporter.new(mpx, sip, false, bufsize, false)

              sip.init(tur, rd_read, tp)
              sid = sip.ship_id

              tur.res.set_consume_listener do |len, resume|
                if resume
                  sip.resume_read(sid)
                end
              end

              st = RudderStateStore.get_store(tur.ship.agent_id).rent
              st.init(rd_read, tp)
              mpx.add_rudder_state(rd_read, st)
              mpx.req_read(rd_read)

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
