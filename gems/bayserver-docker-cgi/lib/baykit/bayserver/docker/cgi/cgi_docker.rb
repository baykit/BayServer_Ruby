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

          # Method to read stdin/stderr
          attr :proc_read_method

          def initialize()
            super
            @interpreter = nil
            @script_base = nil
            @doc_root = nil
            @timeout_sec = CgiDocker::DEFAULT_TIMEOUT_SEC
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

            bufsize = 8192;
            handler = CgiReqContentHandler.new(self, tur)
            tur.req.set_content_handler(handler)
            handler.start_tour(env)
            fname = "cgi#"

            out_rd = handler.std_out_rd
            err_rd = handler.std_err_rd

            agt = GrandAgent.get(tur.ship.agent_id)

            case(BayServer.harbor.cgi_multiplexer)
            when Harbor::MULTIPLEXER_TYPE_SPIDER
              mpx = agt.spider_multiplexer
              out_rd.set_non_blocking
              err_rd.set_non_blocking

            when Harbor::MULTIPLEXER_TYPE_SPIN

              def eof_checker()
                begin
                  pid = Process.wait(handler.pid,  Process::WNOHANG)
                  return pid != nil
                rescue Errno::ECHILD => e
                  BayLog.error_e(e)
                  return true
                end
              end
              mpx = agt.spin_multiplexer
              out_rd.set_non_blocking
              err_rd.set_non_blocking

            when Harbor::MULTIPLEXER_TYPE_TAXI
              mpx = agt.taxi_multiplexer

            when Harbor::MULTIPLEXER_TYPE_JOB
              mpx = agt.job_multiplexer

            else
              raise Sink.new();
            end

            if mpx != nil
              handler.multiplexer = mpx
              out_ship = CgiStdOutShip.new
              out_tp = PlainTransporter.new(agt.net_multiplexer, out_ship, false, bufsize, false)

              out_ship.init_std_out(out_rd, tur.ship.agent_id, tur, out_tp, handler)

              mpx.add_rudder_state(
                out_rd,
                RudderState.new(out_rd, out_tp)
              )

              ship_id = tur.ship.ship_id
              tur.res.set_consume_listener do |len, resume|
                if resume
                  out_ship.resume_read(ship_id)
                end
              end

              err_ship = CgiStdErrShip.new
              err_tp = PlainTransporter.new(agt.net_multiplexer, err_ship, false, bufsize, false)
              err_ship.init_std_err(err_rd, tur.ship.agent_id, handler)
              mpx.add_rudder_state(
                err_rd,
                RudderState.new(err_rd, err_tp)
              )

              mpx.req_read(out_rd)
              mpx.req_read(err_rd)
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