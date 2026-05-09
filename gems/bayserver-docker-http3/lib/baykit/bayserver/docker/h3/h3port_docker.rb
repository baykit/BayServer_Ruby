require 'croute'

require 'baykit/bayserver/docker/base/port_base'
require 'baykit/bayserver/docker/h3/h3_docker'
require 'baykit/bayserver/docker/h3/qic_transporter'
require 'baykit/bayserver/common/rudder_state_store'

module Baykit
  module BayServer
    module Docker
      module H3
        class H3PortDocker < Baykit::BayServer::Docker::Base::PortBase
          include H3Docker

          include Baykit::BayServer
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Common
          include Baykit::BayServer::Docker::Base

          ALPN_PROTOS = %w[h3 h3-29 h3-28 h3-27].freeze

          attr_reader :quic_config, :h3_config

          def initialize
            super
            @quic_config = nil
            @h3_config   = nil
          end

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            super

            if @secure_docker.nil?
              raise Baykit::BayServer::Bcf::ConfigException.new(
                elm.file_name, elm.line_no,
                "H3 port requires a [secure] docker with certFile and keyFile")
            end

            cert = @secure_docker.cert_file
            key  = @secure_docker.key_file
            if cert.nil? || key.nil?
              raise Baykit::BayServer::Bcf::ConfigException.new(
                elm.file_name, elm.line_no,
                BayMessage.get(:CFG_SSL_CERT_FILE_NOT_SPECIFIED))
            end

            # Build the ALPN wire format: each proto is prefixed with its length byte.
            alpn_wire = ALPN_PROTOS.map { |p| p.bytesize.chr + p }.join.b

            @quic_config = Croute::Quic::Config.server(cert, key)
            @quic_config.set_application_protos(alpn_wire)
            @quic_config.set_max_idle_timeout(5_000)
            @quic_config.set_max_recv_udp_payload_size(QicProtocolHandler::MAX_DATAGRAM_SIZE)
            @quic_config.set_max_send_udp_payload_size(QicProtocolHandler::MAX_DATAGRAM_SIZE)
            @quic_config.set_initial_max_data(10_000_000)
            @quic_config.set_initial_max_stream_data_bidi_local(1_000_000)
            @quic_config.set_initial_max_stream_data_bidi_remote(1_000_000)
            @quic_config.set_initial_max_stream_data_uni(1_000_000)
            @quic_config.set_initial_max_streams_bidi(4)
            @quic_config.set_initial_max_streams_uni(4)
            @quic_config.set_disable_active_migration(true)
            @quic_config.enable_early_data

            @h3_config = Croute::H3::Config.new
          end

          ######################################################
          # Implements Port
          ######################################################

          def protocol
            PROTO_NAME
          end

          ######################################################
          # Implements PortBase
          ######################################################

          def support_anchored
            false
          end

          def support_unanchored
            true
          end

          # Called by GrandAgent to create the UDP transporter.
          def new_transporter(agent_id, rd)
            tp = QicTransporter.new
            agt = GrandAgent.get(agent_id)
            tp.init_udp(agent_id, rd, agt.net_multiplexer, self)
            tp
          end
        end
      end
    end
  end
end
