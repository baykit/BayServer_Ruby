require 'openssl'

require 'baykit/bayserver/agent/transporter/transporter'
require 'baykit/bayserver/agent/next_socket_action'

module Baykit
  module BayServer
    module Agent
        module Transporter
          class SecureTransporter < Transporter
            include OpenSSL
            include Baykit::BayServer::Protocol

            attr :sslctx
            attr :ssl_socket

            def initialize(sslctx, server_mode, bufsize, trace_ssl)
              super(server_mode, bufsize, trace_ssl)
              @sslctx = sslctx
            end


            def init(nb_hnd, sip, lis)
              super
              @ssl_socket = SSL::SSLSocket.new(@ch, @sslctx)
              @handshaked = false
            end

            def reset()
              super
              @ssl_socket = nil
            end

            def to_s()
              "stp[#{@data_listener}]"
            end

            ######################################################
            # Implements Transporter
            ######################################################

            def secure()
              return true
            end

            def handshake_nonblock()
              if @server_mode
                @ssl_socket.accept_nonblock()
              else
                @ssl_socket.connect_nonblock()
              end


              BayLog.debug("%s Handshake done", self)
              app_protocols = @ssl_socket.context.alpn_protocols

              # HELP ME
              #   This code does not work!
              #   We cannot get application protocol name
              proto = nil
              if app_protocols != nil && app_protocols.length > 0
                proto = app_protocols[0]
              end
              @data_listener.notify_handshake_done(proto)
            end

            def read_nonblock
              @ssl_socket.read_nonblock(@capacity, @read_buf)
              return nil # client address (for UDP)
            end

            def write_nonblock(buf, adr)
              @ssl_socket.write(buf)
            end

          end
        end

    end
  end
end
