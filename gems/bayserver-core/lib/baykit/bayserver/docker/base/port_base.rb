require 'baykit/bayserver/protocol/protocol_handler_store'
require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/util/object_store'
require 'baykit/bayserver/util/object_factory'

require 'baykit/bayserver/docker/port'
require 'baykit/bayserver/docker/base/docker_base'
require 'baykit/bayserver/common/inbound_ship_store'

module Baykit
  module BayServer
    module Docker
      module Base
        class PortBase < Baykit::BayServer::Docker::Base::DockerBase
          include Baykit::BayServer::Docker::Port #implements

          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Agent::Multiplexer
          include Baykit::BayServer::Docker
          include Baykit::BayServer::Docker::Base
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Rudders
          include Baykit::BayServer::Util
          include Baykit::BayServer::Common

          attr :permission_list
          attr :host
          attr :port
          attr :anchored
          attr :additional_headers
          attr :socket_path
          attr :timeout_sec
          attr :secure_docker
          attr :cities

          def initialize()
            @permission_list = []
            @timeout_sec = -1
            @host = nil
            @port = -1
            @anchored = true
            @additional_headers = []
            @socket_path = nil
            @secure_docker = nil
            @cities = Cities.new()
          end

          def to_s()
            return super + "[#{@port}]"
          end

          ######################################################
          # Abstract methods
          ######################################################
          def support_anchored()
            raise NotImplementedError.new
          end

          def support_unanchored()
            raise NotImplementedError.new
          end

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            if StringUtil.empty?(elm.arg)
              raise ConfigException.new(elm.file_name, elm.line_no, BayMessage.get(:CFG_INVALID_PORT_NAME, elm.name))
            end

            super

            port_name = elm.arg.downcase()
            if port_name.start_with?(":unix:")
              # unix domain sokcet
              @port = -1
              @socket_path = elm.arg[6 .. -1]
              @host = elm.arg
            else
              # TCP or UDP port
              if port_name.start_with?(":tcp:")
                # tcp server socket
                @anchored = true
                host_port = elm.arg[5 .. -1]
              elsif port_name.start_with?(":udp:")
                # udp server socket
                @anchored = false
                host_port = elm.arg[5 .. -1]
              else
                # default: tcp server socket
                @anchored = true
                host_port = elm.arg
              end

              begin
                idx = host_port.index(':')
                if idx != nil
                  @host = host_port[0 .. idx]
                  @port = host_port[idx+1 .. -1].to_i
                else
                  @host = nil
                  @port = host_port.to_i
                end
              rescue => e
                raise ConfigException.new(elm.file_name, elm.line_no, BayMessage.get(:CFG_INVALID_PORT_NAME, elm.name))
              end

              if @anchored
                if !support_anchored()
                  raise ConfigException.new(elm.file_name, elm.line_no, BayMessage.get(:CFG_TCP_NOT_SUPPORTED))
                end
              else
                if !support_unanchored()
                  raise ConfigException.new(elm.file_name, elm.line_no, BayMessage.get(:CFG_UDP_NOT_SUPPORTED))
                end
              end

            end

          end

          ######################################################
          # Implements DockerBase
          ######################################################

          def init_docker(dkr)
            if dkr.kind_of? Permission
              @permission_list.append(dkr)
            elsif dkr.kind_of? City
              @cities.add(dkr)
            elsif dkr.kind_of? Secure
              @secure_docker = dkr
            else
              return super
            end
            return true
          end

          def init_key_val(kv)
            case kv.key.downcase
            when "timeout"
              @timeout_sec = Integer(kv.value)

            when "addheader"
              idx = kv.value.index(':')
              if idx == nil
                raise ConfigException.new(kv.file_name, kv.line_no, BayMessage.get(:CFG_INVALID_PARAMETER_VALUE, kv.value))
              end

              name = kv.value[0 .. idx].strip()
              value = kv.value[idx+1 .. -1].strip()
              @additional_headers << [name, value]

            else
              return super
            end
            return true
          end

          ######################################################
          # implements Port
          ######################################################
          def address()
            if @socket_path
              #  Unix domain socket
              return @socket_path
            elsif @host == nil
              return [@port, "0.0.0.0"]
            else
              return [@port, @host]
            end
          end

          def secure()
            return @secure_docker != nil
          end


          def find_city(name)
            return @cities.find_city(name)
          end

          def on_connected(agt_id, rd)

            check_admitted(rd)

            sip = PortBase.get_ship_store(agt_id).rent()
            agt = GrandAgent.get(agt_id)

            if secure()
              tp = @secure_docker.new_transporter(
                agt_id,
                sip,
                IOUtil.get_sock_recv_buf_size(rd.io))

              ssl_socket = tp.new_ssl_socket(rd.io)
              rd = IORudder.new(ssl_socket)
              if agt.net_multiplexer.is_non_blocking
                rd.set_non_blocking
              end

            else
              size = IOUtil.get_sock_recv_buf_size(rd.io)

              tp = PlainTransporter.new(
                agt.net_multiplexer,
                sip,
                true,
                size,
                false)
            end

            proto_hnd = PortBase.get_protocol_handler_store(protocol(), agt_id).rent()
            sip.init_inbound(rd, agt_id, tp, self, proto_hnd)

            st = RudderState.new(rd, tp)
            agt.net_multiplexer.add_rudder_state(rd, st)
            agt.net_multiplexer.req_read(rd)
          end

          def return_protocol_handler(agt_id, proto_hnd)
            BayLog.debug("%s Return protocol handler", proto_hnd)
            PortBase.get_protocol_handler_store(proto_hnd.protocol, agt_id).Return(proto_hnd)
          end

          def return_ship(sip)
            BayLog.debug("%s end (return ship)", sip)
            PortBase.get_ship_store(sip.agent_id).Return(sip)
          end

          ######################################################
          # Private methods
          ######################################################
          private

          def check_admitted(rd)
            @permission_list.each do |perm_dkr|
              perm_dkr.socket_admitted(rd)
            end
          end

          def PortBase.get_ship_store(agt_id)
            return InboundShipStore.get_store(agt_id)
          end

          def PortBase.get_protocol_handler_store(proto, agt_id)
            return ProtocolHandlerStore.get_store(proto, true, agt_id)
          end

        end
      end
    end 
  end 
end 

