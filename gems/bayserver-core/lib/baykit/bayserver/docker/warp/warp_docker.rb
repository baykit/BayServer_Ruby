require 'uri'

require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/lifecycle_listener'
require 'baykit/bayserver/docker/base/club_base'
require 'baykit/bayserver/docker/warp/warp_data'
require 'baykit/bayserver/docker/warp/warp_data_listener'
require 'baykit/bayserver/docker/warp/warp_ship_store'

module Baykit
  module BayServer
    module Docker
      module Warp
        class WarpDocker  < Baykit::BayServer::Docker::Base::ClubBase

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util
          include Baykit::BayServer::Docker::Warp

          class AgentListener
            include Baykit::BayServer::Agent::LifecycleListener

            attr :warp_docker

            def initialize(dkr)
              @warp_docker = dkr
            end

            def add(agt)
              @warp_docker.stores[agt.agent_id] = WarpShipStore.new(@warp_docker.max_ships);
            end

            def remove(agt)
              @warp_docker.stores.delete(agt.agent_id);
            end
          end


          class WarpShipHolder
            attr :owner_id
            attr :ship_id
            attr :ship

            def initialize(owner_id, ship_id, ship)
              @owner_id = owner_id
              @ship_id = ship_id
              @ship = ship
            end
          end

          attr :scheme
          attr :host
          attr :port
          attr :warp_base
          attr :max_ships
          attr :cur_ships
          attr :host_addr
          attr :timeout_sec
          attr :tour_list
          attr :lock

          # Agent ID => WarpShipStore
          attr :stores

          ######################################################
          # Abstract methods
          ######################################################
          #
          #
          #     public abstract boolean secure();
          #     protected abstract String protocol();
          #     protected abstract Transporter newTransporter(ShipAgent agent, SocketChannel ch);
          #

          def initialize
            super
            @scheme = nil
            @host = nil
            @port = 0
            @warp_base = nil
            @max_ships = -1
            @cur_ships = 0
            @host_addr = nil
            @tour_list = []
            @timeout_sec = -1 #  -1 means "Use harbor.socketTimeoutSec"
            @stores = {}
            @lock = Mutex.new
          end

          ######################################################
          # Implements DockerBase
          ######################################################

          def init(elm, parent)
            super

            if @warp_base == nil
              @warp_base = "/"
            end

            @host_addr = []
            if @host && @host.start_with?(":unix:")
              @host_addr << :UNIX
              @host_addr <<  Socket.sockaddr_un(@host[6 .. -1])
              @port = -1
            else

              if @port <= 0
                @port = 80
              end

              @host_addr << :INET

              begin
                addrs = Addrinfo.getaddrinfo(@host, @port, nil, :STREAM)
              rescue SocketError => e
                BayLog.error_e(e)
                raise ConfigException.new(elm.file_name, elm.line_no, "Invalid address: %s:%d", @host, @port)
              end
              inet4_addr = nil
              inet6_addr = nil
              if addrs
                addrs.each do |adr|
                  if adr.ipv4?
                    inet4_addr = adr
                  elsif adr.ipv6?
                    inet6_addr = adr
                  end
                end
              end

              if inet4_addr
                @host_addr << inet4_addr
              elsif inet6_addr
                @host_addr << inet6_addr
              else
                raise ConfigException.new(elm.file_name, elm.line_no, "Host not found: %s", @host)
              end



            end

            GrandAgent.add_lifecycle_listener(AgentListener.new(self));

            BayLog.info("WarpDocker[%s] host=%s port=%d adr=%s", @warp_base, @host, @port, @host_addr)
          end

          def init_key_val(kv)
            case kv.key.downcase

            when "destcity"
              @host = kv.value

            when "destport"
              @port = kv.value.to_i

            when "desttown"
              @warp_base = kv.value
              if !@warp_base.end_with?("/")
                @warp_base += "/"
              end

            when "maxships"
              @max_ships = kv.value.to_i

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
            agt = tur.ship.agent
            sto = get_ship_store(agt.agent_id)

            wsip = sto.rent()
            if wsip == nil
              BayLog.warn("%s Busy!", self)
              raise HttpException.new HttpStatus::INTERNAL_SERVER_ERROR, "WarpDocker busy"
            end

            begin
              BayLog.trace("%s got from store", wsip)
              need_connect = false

              if !wsip.initialized
                if @host_addr[0] == :UNIX
                  skt = Socket.new(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
                else
                  skt = Socket.new(@host_addr[1].ipv4? ? Socket::AF_INET : Socket::AF_INET6, Socket::SOCK_STREAM, 0)
                end
                skt.nonblock = true

                tp = new_transporter(agt, skt)
                proto_hnd = ProtocolHandlerStore.get_store(protocol(), false, agt.agent_id).rent()
                wsip.init_warp(skt, agt, tp, self, proto_hnd)
                tp.init(agt.non_blocking_handler, skt, WarpDataListener.new(wsip))
                BayLog.debug("%s init warp ship", wsip)
                BayLog.debug("%s Connect to %s:%d skt=%s", wsip, @host, @port, skt)

                need_connect = true
              end

              @lock.synchronize do
                @tour_list.append(tur)
              end

              wsip.start_warp_tour(tur)

              if need_connect
                agt.non_blocking_handler.add_channel_listener(wsip.socket, tp)
                agt.non_blocking_handler.ask_to_connect(wsip.socket, @host_addr[1])
              end

            rescue SystemCallError => e
              wsip.end_warp_tour(tur)
              raise e
            rescue HttpException => e
              raise e
            end

          end



          ######################################################
          # Implements WarpDocker
          ######################################################
          def keep_ship(wsip)
            BayLog.debug("%s keepShip: %s", self, wsip)
            get_ship_store(wsip.agent.agent_id).keep(wsip)
          end

          def return_ship(wsip)
            BayLog.debug("%s return ship: %s", self, wsip);
            get_ship_store(wsip.agent.agent_id).Return(wsip)
          end

          def return_protocol_handler(agt, phnd)
            BayLog.debug("%s Return protocol handler: ", phnd)
            get_protocol_handler_store(agt.agent_id).Return(phnd)
          end

          ######################################################
          # Other methods
          ######################################################
          def get_ship_store(agent_id)
            return @stores[agent_id]
          end

          ######################################################
          # private methods
          ######################################################
          private

          def get_protocol_handler_store(agt_id)
            return ProtocolHandlerStore.get_store(protocol(), false, agt_id)
          end
        end
      end
    end
  end
end

