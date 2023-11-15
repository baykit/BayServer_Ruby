require 'baykit/bayserver/bcf/bcf_parser'
require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/docker/built_in/built_in_harbor_docker'
require 'baykit/bayserver/util/sys_util'

module Baykit
  module BayServer
    module Agent
      module Signal
        class SignalSender
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Docker::BuiltIn
          include Baykit::BayServer::Util


          attr :control_port
          attr :pid_file

          def initialize
            @bay_port = BuiltInHarborDocker::DEFAULT_CONTROL_PORT
            @pid_file = BuiltInHarborDocker::DEFAULT_PID_FILE
          end


          #
          # Send running BayServer a command
          #
          def send_command(cmd)
            parse_bay_port(BayServer.bserv_plan)

            if @bay_port < 0
              pid = read_pid_file()
              sig = SignalAgent.get_signal_from_command(cmd)
              if sig == nil
                raise StandardError("Invalid command: " + cmd)
              else
                kill(pid, sig)
              end
            else
              BayLog.info(BayMessage.get(:MSG_SENDING_COMMAND, cmd))
              send("127.0.0.1", @bay_port, cmd)
            end
          end

          #
          # Parse plan file and get port number of SignalAgent
          #
          def parse_bay_port(plan)
            p = BcfParser.new()
            doc = p.parse(plan)
            doc.content_list.each do |elm|
              if elm.kind_of?(BcfElement)
                if elm.name.casecmp?("harbor")
                  elm.content_list.each do |kv|
                    if kv.key.casecmp?("controlPort")
                      @bay_port = kv.value.to_i()
                    elsif kv.key.casecmp?("pidFile")
                      @pid_file = kv.value
                    end
                  end
                end
              end
            end
          end


          def send(host, port, cmd)
            begin
              a = Addrinfo.tcp(host, port)
              s = Socket.new(a.ipv4? ? Socket::AF_INET : Socket::AF_INET6, Socket::SOCK_STREAM)
              s.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [60, 0].pack("l_2"))
              s.connect(a)
              s.write(cmd + "\n")
              s.flush();
              line = s.readline()
            ensure
              s.close()
            end
          end

          def kill(pid, sig)
            BayLog.info("Send signal pid=#{pid} sig=#{sig}")
            if SysUtil.run_on_windows()
              system("taskkill /PID #{pid} /F")
            else
              Process.kill(sig, pid)
            end
          end

          def read_pid_file()
            File.open(BayServer.get_location(@pid_file), "r") do |f|
              return f.readline().to_i()
            end
          end
        end
      end
    end
  end
end

