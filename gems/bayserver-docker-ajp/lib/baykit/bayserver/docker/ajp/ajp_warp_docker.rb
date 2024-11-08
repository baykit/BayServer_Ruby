require 'baykit/bayserver/docker/base/warp_base'
require 'baykit/bayserver/docker/ajp/package'
require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/util/io_util'
require 'baykit/bayserver/protocol/packet_store'

module Baykit
  module BayServer
    module Docker
      module Ajp
        class AjpWarpDocker < Baykit::BayServer::Docker::Base::WarpBase
          include Baykit::BayServer::Docker::Ajp::AjpDocker  # implements

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Agent::Multiplexer
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Util

          ######################################################
          # Implements WarpDocker
          ######################################################
          def secure()
            return false
          end

          ######################################################
          # Implements WarpDockerBase
          ######################################################
          private
          def protocol()
            return PROTO_NAME
          end

          def new_transporter(agt, rd, sip)
            tp = PlainTransporter.new(agt.net_multiplexer, sip, false, IOUtil.get_sock_recv_buf_size(rd.io), false)
            tp.init
            return tp
          end

          ######################################################
          # Class initializer
          ######################################################
          begin
            PacketStore.register_protocol(
              PROTO_NAME,
              AjpPacketFactory.new()
            )
            ProtocolHandlerStore.register_protocol(
              PROTO_NAME,
              false,
              AjpWarpHandler::WarpProtocolHandlerFactory.new())
          end
        end
      end
    end
  end
end

