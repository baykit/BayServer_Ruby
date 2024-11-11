require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/agent/transporter/spin_read_transporter'
require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/tours/read_file_taxi'
require 'baykit/bayserver/docker/base/club_base'
require 'baykit/bayserver/docker/harbor'
require 'baykit/bayserver/docker/cgi/cgi_req_content_handler'
require 'baykit/bayserver/docker/cgi/cgi_std_out_ship'
require 'baykit/bayserver/docker/cgi/cgi_std_err_ship'
require 'baykit/bayserver/docker/cgi/cgi_message'
require 'baykit/bayserver/taxi/taxi_runner'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/util/cgi_util'
require 'baykit/bayserver/util/sys_util'

module Baykit
  module BayServer
    module Docker
      module Cgi
        class CgiDocker < Baykit::BayServer::Docker::Base::ClubBase
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Agent::Multiplexer
          include Baykit::BayServer::Docker
          include Baykit::BayServer::Docker::Cgi
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Taxi
          include Baykit::BayServer::Rudders

          DEFAULT_TIMEOUT_SEC = 0

          attr :interpreter
          attr :script_base
          attr :doc_root
          attr :timeout_sec
          attr :max_processes
          attr :process_count
          attr :wait_count


          def initialize()
            super
            @interpreter = nil
            @script_base = nil
            @doc_root = nil
            @timeout_sec = CgiDocker::DEFAULT_TIMEOUT_SEC
            @max_processes = -1
            @process_count = 0
            @wait_count = 0
          end

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            super
          end


          ######################################################
          # Implements DockerBase
          ######################################################

          def init_key_val(kv)
            case kv.key.downcase
            when "interpreter"
              @interpreter = kv.value

            when "scriptbase"
              @script_base = kv.value

            when "docroot"
              @doc_root = kv.value

            when "timeout"
              @timeout_sec = kv.value.to_i

            when "maxprocesses"
              @max_processes = kv.value.to_i

            else
              return super
            end
            return true
          end

          ######################################################
          # Implements Club
          ######################################################

          def arrive(tur)

            if tur.req.uri.include?("..")
              raise HttpException.new(HttpStatus::FORBIDDEN, tur.req.uri)
              return
            end

            base = script_base
            if base == nil
              base = tur.town.location()
            end

            if StringUtil.empty?(base)
              raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR, "%s scriptBase of cgi docker or location of town is not specified.", tur.town)
            end

            root = doc_root
            if root == nil
              root = tur.town.location()
            end

            if StringUtil.empty?(root)
              raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR, "$s docRoot of cgi docker or location of town is not specified.", tur.town)
            end

            env = CgiUtil.get_env_hash(tur.town.name, root, base, tur)
            if BayServer.harbor.trace_header
              env.keys.each do |name|
                value = env[name]
                BayLog.info("%s cgi: env: %s=%s", tur, name, value)
              end
            end

            file_name = env[CgiUtil::SCRIPT_FILENAME]
            if !File.file?(file_name)
              raise HttpException.new(HttpStatus::NOT_FOUND, file_name)
            end

            handler = CgiReqContentHandler.new(self, tur, env)
            tur.req.set_content_handler(handler)
            handler.req_start_tour()
          end

          def create_command(env)
            script = env[CgiUtil::SCRIPT_FILENAME]
            if @interpreter == nil
              command = script
            else
              command = @interpreter + " " + script
            end
            command
          end

          ######################################################
          # Other methods
          ######################################################

          def get_wait_count
            @wait_count
          end

          def add_process_count
            if @max_processes <= 0 || @process_count < @max_processes
              @process_count += 1
              BayLog.debug("%s Process count: %d", self, @process_count)
              return true
            end

            @wait_count += 1
            return false
          end

          def sub_process_count
            return @process_count -= 1
          end

          def sub_wait_count
            return @wait_count -= 1
          end
        end
      end
    end
  end
end