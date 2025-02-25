require 'baykit/bayserver/protocol/packet_store'
require 'baykit/bayserver/util/io_util'
require 'baykit/bayserver/util/string_util'

require 'baykit/bayserver/docker/base/port_base'
require 'baykit/bayserver/docker/http/htp_docker'
require 'baykit/bayserver/docker/http/h1/package'
require 'baykit/bayserver/docker/http/h2/package'

module Baykit
  module BayServer
    module Docker
      module Http
        class HtpPortDocker < Baykit::BayServer::Docker::Base::PortBase
          include Baykit::BayServer::Docker::Http::HtpDocker # implements

          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Util
          include Baykit::BayServer::Docker::Base
          include Baykit::BayServer::Docker::Http
          include Baykit::BayServer::Docker::Http::H1
          include Baykit::BayServer::Docker::Http::H2

          DEFAULT_SUPPORT_H2 = true

          attr :support_h2

          def initialize
            super
            @support_h2 = DEFAULT_SUPPORT_H2
          end

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            super

            if @support_h2
              if @secure_docker != nil
                @secure_docker.set_app_protocols(["h2", "http/1.1"])
              end
              H2ErrorCode.init()
            end
          end

          ######################################################
          # Implements DockerBase
          ######################################################

          def init_key_val(kv)
            case kv.key.downcase
            when "supporth2", "enableh2"
              @support_h2 = StringUtil.parse_bool(kv.value)
            else
              return super
            end
            return true
          end

          ######################################################
          # Implements Port
          ######################################################

          def protocol()
            return H1_PROTO_NAME
          end

          ######################################################
          # Implements PortBase
          ######################################################
          def support_anchored()
            return true
          end

          def support_unanchored()
            return false
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
              true,
              H1InboundHandler::InboundProtocolHandlerFactory.new())
            ProtocolHandlerStore.register_protocol(
              H2_PROTO_NAME,
              true,
              H2InboundHandler::InboundProtocolHandlerFactory.new())
          end
        end
      end
    end
  end
end
