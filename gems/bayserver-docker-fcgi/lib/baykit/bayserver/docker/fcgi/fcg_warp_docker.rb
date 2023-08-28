require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/docker/warp/warp_docker'
require 'baykit/bayserver/agent/transporter/plain_transporter'
require 'baykit/bayserver/docker/fcgi/package'

module Baykit
  module BayServer
    module Docker
      module Fcgi
        class FcgWarpDocker < Baykit::BayServer::Docker::Warp::WarpDocker
          include Baykit::BayServer::Docker::Fcgi::FcgDocker  # implements

          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Agent::Transporter

          attr :script_base
          attr :doc_root

          ######################################################
          # Implements Docker
          ######################################################
          def init(elm, parent)
            super

            if @script_base == nil
              BayLog.warn "FCGI: docRoot is not specified"
            end
          end

          ######################################################
          # Implements DockerBase
          ######################################################

          def init_key_val(kv)
            case kv.key.downcase
            when "scritbase"
              @script_base = kv.value
            when "docroot"
              @doc_root = kv.value
            else
              return super
            end
            true
          end

          ######################################################
          # Implements WarpDocker
          ######################################################
          def secure()
            return false
          end

          ######################################################
          # Implements WarpDockerBase
          ######################################################
          def protocol()
            return PROTO_NAME
          end

          def new_transporter(agt, skt)
            PlainTransporter.new(false, IOUtil.get_sock_recv_buf_size(skt))
          end

          ######################################################
          # Class initializer
          ######################################################
          begin
            PacketStore.register_protocol(
              PROTO_NAME,
              FcgPacketFactory.new())
            ProtocolHandlerStore.register_protocol(
              PROTO_NAME,
              false,
              FcgWarpHandler::WarpProtocolHandlerFactory.new())
          end
        end
      end
    end
  end
end
