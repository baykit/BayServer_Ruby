require 'baykit/bayserver/mem_usage'
require 'baykit/bayserver/bcf/package'

require 'baykit/bayserver/agent/signal/signal_proxy'
require 'baykit/bayserver/util/sys_util'

module Baykit
  module BayServer
    module Agent
      module Signal
        class SignalAgent
          include Baykit::BayServer
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent::Signal

          COMMAND_RELOAD_CERT = "reloadcert"
          COMMAND_MEM_USAGE = "memusage"
          COMMAND_RESTART_AGENTS = "restartagents"
          COMMAND_SHUTDOWN = "shutdown"
          COMMAND_ABORT = "abort"

          class << self
            attr :commands
            attr :signal_map
            attr :signal_agent
          end

          @commands = [
            COMMAND_RELOAD_CERT,
            COMMAND_MEM_USAGE,
            COMMAND_RESTART_AGENTS,
            COMMAND_SHUTDOWN,
            COMMAND_ABORT
          ]
          @signal_map = {}
          @signal_agent = nil

          attr :port
          attr :server_skt

          def initialize(port)
            @port = port
            @server_skt = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
            @server_skt.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
            adr = Socket.sockaddr_in(@port, "127.0.0.1")
            @server_skt.bind(adr)
            @server_skt.listen(0)
            BayLog.info( BayMessage.get(:MSG_OPEN_CTL_PORT, @port))
          end

          def on_socket_readable()

            begin
              skt, = @server_skt.accept
              skt.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [5, 0].pack("l_2"))

              line = skt.readline.strip()
              BayLog.info(BayMessage.get(:MSG_COMMAND_RECEIVED, line))
              SignalAgent.handle_command(line)
              skt.write("OK\n")
              skt.flush

            rescue => e
              BayLog.error_e(e)

            ensure
              if skt
                skt.close()
              end
            end

          end

          def close
            @server_skt.close
          end


          ######################################################
          # class methods
          ######################################################

          def SignalAgent.init(bay_port)
            @commands.each do |cmd|
              SignalProxy.register(get_signal_from_command(cmd)) do
                handle_command(cmd)
              end
            end

            if bay_port > 0
              @signal_agent = SignalAgent.new(bay_port)
            end
          end

          def SignalAgent.handle_command(cmd)
            BayLog.debug("handle command: %s", cmd)
            case (cmd.downcase)
            when COMMAND_RELOAD_CERT
              GrandAgent.reload_cert_all()
            when COMMAND_MEM_USAGE
              GrandAgent.print_usage_all()
            when COMMAND_RESTART_AGENTS
              GrandAgent.restart_all()
            when COMMAND_SHUTDOWN
              GrandAgent.shutdown_all()
            when COMMAND_ABORT
              GrandAgent.abort_all()
            else
              BayLog.error("Unknown command: %s", cmd)
            end
          end


          def SignalAgent.get_signal_from_command(command)
            init_signal_map()
            @signal_map.keys().each do |sig|
              if(@signal_map[sig].casecmp?(command))
                return sig;
              end
            end
            return nil
          end

          def SignalAgent.init_signal_map()
            if !@signal_map.empty?
              return;
            end

            if SysUtil.run_on_windows()
              # Available signals on Windows
              #    SIGABRT
              #    SIGFPE
              #    SIGILL
              #    SIGINT
              #    SIGSEGV
              #    SIGTERM
              @signal_map["SEGV"] = COMMAND_RELOAD_CERT
              @signal_map["ILL"] = COMMAND_MEM_USAGE
              @signal_map["INT"] = COMMAND_SHUTDOWN
              @signal_map["TERM"] = COMMAND_RESTART_AGENTS
              @signal_map["ABRT"] = COMMAND_ABORT

            else
              @signal_map["ALRM"] = COMMAND_RELOAD_CERT
              @signal_map["TRAP"] = COMMAND_MEM_USAGE
              @signal_map["HUP"] = COMMAND_RESTART_AGENTS
              @signal_map["TERM"] = COMMAND_SHUTDOWN
              @signal_map["ABRT"] = COMMAND_ABORT
            end
          end

          def SignalAgent.term()
            if @signal_agent
              @signal_agent.close()
            end
          end
        end
      end
    end
  end
end

