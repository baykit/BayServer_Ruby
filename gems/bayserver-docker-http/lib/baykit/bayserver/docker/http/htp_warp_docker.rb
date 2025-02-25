require 'openssl'

require 'baykit/bayserver/docker/base/port_base'
require 'baykit/bayserver/docker/base/warp_base'
require 'baykit/bayserver/protocol/packet_store'
require 'baykit/bayserver/docker/http/h1/package'
require 'baykit/bayserver/docker/http/h2/package'


module Baykit
  module BayServer
    module Docker
      module Http
        class HtpWarpDocker < Baykit::BayServer::Docker::Base::WarpBase
          include Baykit::BayServer::Docker::Http::HtpDocker # implements

          include OpenSSL
          include Baykit::BayServer::Agent::Transporter
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Docker::Http::H1
          include Baykit::BayServer::Docker::Http::H2

          attr :secure
          attr :support_h2
          attr :ssl_ctx
          attr :trace_ssl

          def initialize
            super
            @secure = false
            @support_h2 = true
            @ssl_ctx = nil
            @trace_ssl = false
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

          end

          ######################################################
          # Implements DockerBase
          ######################################################

          def init_key_val(kv)
            case kv.key.downcase
            when "supporth2"
              @support_h2 = StringUtil.(kv.value)

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
            return H1_PROTO_NAME
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

