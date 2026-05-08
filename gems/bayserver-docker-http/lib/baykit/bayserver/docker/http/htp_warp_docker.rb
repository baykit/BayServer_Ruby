require 'openssl'

require 'baykit/bayserver/docker/base/port_base'
require 'baykit/bayserver/docker/base/warp_base'
require 'baykit/bayserver/protocol/packet_store'
require 'baykit/bayserver/docker/http/h1/package'
require 'baykit/bayserver/docker/http/h2/package'
require 'baykit/bayserver/docker/http/warp_ship_pool'


module Baykit
  module BayServer
    module Docker
      module Http
        class HtpWarpDocker < Baykit::BayServer::Docker::Base::WarpBase
          include Baykit::BayServer::Docker::Http::HtpDocker # implements

          include OpenSSL
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Docker::Http::H1
          include Baykit::BayServer::Docker::Http::H2
          include Baykit::BayServer::Agent

          attr :secure
          attr :support_h2
          attr :enable_h2
          attr :ssl_ctx
          attr :trace_ssl

          # Agent ID => WarpShipPool (only populated when @enable_h2 is true)
          attr :pools

          def initialize
            super
            @secure = false
            @support_h2 = true
            @enable_h2 = false
            @ssl_ctx = nil
            @trace_ssl = false
            @pools = {}
          end

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            super

            if @secure
              begin
                @ssl_ctx = SSL::SSLContext.new
              rescue => e
                BayLog.error_e(e)
                raise ConfigException.new(elm.file_name, elm.line_no, BayMessage.get(:CFG_SSL_INIT_ERROR, e))
              end
            end

            if @enable_h2
              # The base WarpBase already registered a listener that owns the
              # per-agent WarpShipStore. We add a second one here, scoped to
              # multiplex pools, so every spawned agent gets a pool entry.
              GrandAgent.add_lifecycle_listener(PoolAgentListener.new(self))
            end
          end

          ######################################################
          # Implements DockerBase
          ######################################################

          def init_key_val(kv)
            case kv.key.downcase
            when "supporth2"
              @support_h2 = StringUtil.parse_bool(kv.value)

            when "enableh2"
              @enable_h2 = StringUtil.parse_bool(kv.value)

            when "tracessl"
              @trace_ssl = StringUtil.parse_bool(kv.value)

            when "secure"
              @secure = StringUtil.parse_bool(kv.value)
            else
              return super
            end

            return true;
          end

          ######################################################
          # Implements WarpDocker
          ######################################################

          def secure()
            return @secure
          end

          ######################################################
          # Implements WarpDockerBase
          ######################################################

          def protocol()
            # When enableh2 is set, the warp speaks HTTP/2 from the start:
            #   secure=false -> h2c (cleartext H2 with prior knowledge)
            #   secure=true  -> h2 over TLS without ALPN negotiation
            @enable_h2 ? H2_PROTO_NAME : H1_PROTO_NAME
          end

          def new_transporter(agt, rd, sip)
            if @secure
              tp =  SecureTransporter.new(
                agt.net_multiplexer,
                sip,
                false,
                false, IOUtil.get_sock_recv_buf_size(rd.io),
                @trace_ssl,
                @ssl_ctx)
            else
              tp = PlainTransporter.new(
                agt.net_multiplexer,
                sip,
                false,
                IOUtil.get_sock_recv_buf_size(rd.io),
                false)
            end
            tp.init
            return tp
          end

          ######################################################
          # Multiplex hooks (only active when enable_h2 is true)
          ######################################################

          def pick_reusable_ship(agt, tour)
            return nil unless @enable_h2
            pool = @pools[agt.agent_id]
            pool ? pool.find_idlest : nil
          end

          def on_ship_rented(agt, wsip)
            return unless @enable_h2
            pool = @pools[agt.agent_id]
            pool.add(wsip) if pool
          end

          def keep(wsip)
            if @enable_h2
              # Multiplex mode: ship stays in the per-agent pool until the
              # backend connection closes. Returning it to the WarpShipStore
              # keepList would yank the ship out of the reuse pool.
              return
            end
            super
          end

          def on_end_ship(wsip)
            if @enable_h2
              pool = @pools[wsip.agent_id]
              pool.remove(wsip) if pool
            end
            super
          end

          def exclude_from_pool(wsip)
            return unless @enable_h2
            pool = @pools[wsip.agent_id]
            pool.remove(wsip) if pool
          end

          ######################################################
          # Inner classes
          ######################################################

          class PoolAgentListener
            include Baykit::BayServer::Agent::LifecycleListener

            def initialize(dkr)
              @docker = dkr
            end

            def add(agt_id)
              @docker.pools[agt_id] = WarpShipPool.new
            end

            def remove(agt_id)
              @docker.pools.delete(agt_id)
            end
          end

          ######################################################
          # Class initializer
          ######################################################
          begin
            PacketStore.register_protocol(
              H1_PROTO_NAME,
              H1PacketFactory.new())
            PacketStore.register_protocol(
              H2_PROTO_NAME,
              H2PacketFactory.new())
            ProtocolHandlerStore.register_protocol(
              H1_PROTO_NAME,
              false,
              H1WarpHandler::WarpProtocolHandlerFactory.new())
            ProtocolHandlerStore.register_protocol(
              H2_PROTO_NAME,
              false,
              H2WarpHandler::WarpProtocolHandlerFactory.new())
          end
        end
      end
    end
  end
end
