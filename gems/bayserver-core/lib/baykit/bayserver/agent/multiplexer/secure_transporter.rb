require 'openssl'

require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/agent/next_socket_action'

module Baykit
  module BayServer
    module Agent
        module Multiplexer
          class SecureTransporter < PlainTransporter
            include OpenSSL
            include Baykit::BayServer::Protocol

            attr :sslctx

            def initialize(mpx, sip, server_mode, bufsize, trace_ssl, sslctx)
              super(mpx, sip, server_mode, bufsize, trace_ssl)
              @sslctx = sslctx
            end


            def to_s()
              "stp[#{@ship}]"
            end

            ######################################################
            # Implements Transporter
            ######################################################

            def secure()
              return true
            end

            def on_read(rd, buf, len)
              super
            end

            ######################################################
            # Custom methods
            ######################################################

            def new_ssl_socket(skt)
              SSL::SSLSocket.new(skt, @sslctx)
            end
          end
        end

    end
  end
end
