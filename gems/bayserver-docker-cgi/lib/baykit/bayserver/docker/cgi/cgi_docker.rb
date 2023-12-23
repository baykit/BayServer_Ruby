require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/agent/transporter/plain_transporter'
require 'baykit/bayserver/agent/transporter/spin_read_transporter'
require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/tours/read_file_taxi'
require 'baykit/bayserver/docker/base/club_base'
require 'baykit/bayserver/docker/harbor'
require 'baykit/bayserver/docker/cgi/cgi_req_content_handler'
require 'baykit/bayserver/docker/cgi/cgi_std_out_yacht'
require 'baykit/bayserver/docker/cgi/cgi_std_err_yacht'
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
          include Baykit::BayServer::Agent::Transporter
          include Baykit::BayServer::Docker
          include Baykit::BayServer::Docker::Cgi
          include Baykit::BayServer::Tours
          include Baykit::BayServer::Taxi

          DEFAULT_PROC_READ_METHOD = Harbor::FILE_SEND_METHOD_TAXI
          DEFAULT_TIMEOUT_SEC = 0

          attr :interpreter
          attr :script_base
          attr :doc_root
          attr :timeout_sec

          # Method to read stdin/stderr
          attr :proc_read_method

          def initialize()
            super
            @interpreter = nil
            @script_base = nil
            @doc_root = nil
            @proc_read_method = CgiDocker::DEFAULT_PROC_READ_METHOD
            @timeout_sec = CgiDocker::DEFAULT_TIMEOUT_SEC
          end

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            super

            if @proc_read_method == Harbor::FILE_SEND_METHOD_SELECT and !SysUtil.support_select_pipe()
              BayLog.warn(BayMessage.get(:CGI_PROC_READ_METHOD_SELECT_NOT_SUPPORTED))
              @proc_read_method = Harbor::FILE_SEND_METHOD_TAXI
            end

            if @proc_read_method == Harbor::FILE_SEND_METHOD_SPIN and !SysUtil.support_nonblock_pipe_read()
              BayLog.warn(BayMessage.get(:CGI_PROC_READ_METHOD_SPIN_NOT_SUPPORTED))
              @proc_read_method = Harbor::FILE_SEND_METHOD_TAXI
            end
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

            when "processreadmethod"
              case kv.value.downcase()

              when "select"
                @proc_read_method = Harbor::FILE_SEND_METHOD_SELECT

              when "spin"
                @proc_read_method = Harbor::FILE_SEND_METHOD_SPIN

              when "taxi"
                @proc_read_method = Harbor::FILE_SEND_METHOD_TAXI

              else
                raise ConfigException.new(kv.file_name, kv.line_no, BayMessage.get(:CFG_INVALID_PARAMETER_VALUE, kv.value))
              end

            when "timeout"
              @timeout_sec = kv.value.to_i

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
            if BayServer.harbor.trace_header?
              env.keys.each do |name|
                value = env[name]
                BayLog.info("%s cgi: env: %s=%s", tur, name, value)
              end
            end

            file_name = env[CgiUtil::SCRIPT_FILENAME]
            if !File.file?(file_name)
              raise HttpException.new(HttpStatus::NOT_FOUND, file_name)
            end

            bufsize = 8192;
            handler = CgiReqContentHandler.new(self, tur)
            tur.req.set_content_handler(handler)
            handler.start_tour(env)
            fname = "cgi#"

            out_yat = CgiStdOutYacht.new()
            err_yat = CgiStdErrYacht.new()

            case(@proc_read_method)
            when Harbor::FILE_SEND_METHOD_SELECT
              out_tp = PlainTransporter.new(false, bufsize)
              out_yat.init(tur, out_tp, handler)
              out_tp.init(tur.ship.agent.non_blocking_handler, handler.std_out[0], out_yat)
              out_tp.open_valve()

              err_tp = PlainTransporter.new(false, bufsize)
              err_yat.init(tur, handler)
              err_tp.init(tur.ship.agent.non_blocking_handler, handler.std_err[0], err_yat)
              err_tp.open_valve()

            when Harbor::FILE_SEND_METHOD_SPIN

              def eof_checker()
                begin
                  pid = Process.wait(handler.pid,  Process::WNOHANG)
                  return pid != nil
                rescue Errno::ECHILD => e
                  BayLog.error_e(e)
                  return true
                end
              end

              out_tp = SpinReadTransporter.new(bufsize)
              out_yat.init(tur, out_tp, handler)
              out_tp.init(tur.ship.agent.spin_handler, out_yat, handler.std_out[0], -1, @timeout_sec, eof_checker)
              out_tp.open_valve()

              err_tp = SpinReadTransporter.new(bufsize)
              err_yat.init(tur, handler)
              err_tp.init(tur.ship.agent.spin_handler, err_yat, handler.std_out[0], -1, @timeout_sec, eof_checker)
              err_tp.open_valve()

            when Harbor::FILE_SEND_METHOD_TAXI
              out_txi = ReadFileTaxi.new(tur.ship.agent.agent_id, bufsize)
              out_yat.init(tur, out_txi, handler)
              out_txi.init(handler.std_out[0], out_yat)
              if !TaxiRunner.post(tur.ship.agent.agent_id, out_txi)
                raise HttpException.new(HttpStatus.SERVICE_UNAVAILABLE, "Taxi is busy!")
              end

              err_txi = ReadFileTaxi.new(tur.ship.agent.agent_id, bufsize)
              err_yat.init(tur, handler)
              err_txi.init(handler.std_err[0], err_yat)
              if !TaxiRunner.post(tur.ship.agent.agent_id, err_txi)
                raise HttpException.new(HttpStatus.SERVICE_UNAVAILABLE, "Taxi is busy!")
              end

            else
              raise Sink.new();
            end
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
        end
      end
    end
  end
end