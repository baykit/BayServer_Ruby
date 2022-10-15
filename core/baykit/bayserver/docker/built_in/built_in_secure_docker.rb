require 'openssl'

require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/agent/transporter/secure_transporter'

require 'baykit/bayserver/docker/secure'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Docker
      module BuiltIn
        class BuiltInSecureDocker < Baykit::BayServer::Docker::Base::DockerBase
          include Baykit::BayServer::Docker::Secure  # implements

          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Agent::Transporter
          include Baykit::BayServer::Util
          include OpenSSL

          DEFAULT_CLIENT_AUTH = false
          DEFAULT_SSL_PROTOCOL = "TLS"

          # SSL setting
          attr :key_store
          attr :key_store_pass
          attr :client_auth
          attr :ssl_protocol
          attr :key_file
          attr :cert_file
          attr :certs
          attr :certs_pass
          attr :trace_ssl
          attr :sslctx
          attr :app_protocols

          def initialize
            @client_auth = DEFAULT_CLIENT_AUTH
            @ssl_protocol = DEFAULT_SSL_PROTOCOL
            @app_protocols = []
          end

          ######################################################
          # Implements Docker
          ######################################################

          def init(elm, parent)
            super

            if (@key_store == nil) && ((@key_file == nil) || (@cert_file == nil))
              raise ConfigException.new(elm.file_name, elm.line_no, "Key file or cert file is not specified")
            end

            begin
              init_ssl()
            rescue ConfigException => e
              raise e
            rescue => e
              BayLog.error_e(e)
              raise ConfigException.new(elm.file_name, elm.line_no, BayMessage.get(:CFG_SSL_INIT_ERROR, e.message))
            end
          end

          ######################################################
          # Implements DockerBase
          ######################################################

          def init_key_val(kv)
            case kv.key.downcase
            when "key"
              @key_file = get_file_path(kv.value)
            when "cert"
              @cert_file = get_file_path(kv.value)
            when "keystore"
              @key_store = get_file_path(kv.value)
            when "keystorepass"
              @key_store_pass = kv.value
            when "clientauth"
              @client_auth = StringUtil.parse_bool(kv.value)
            when "sslprotocol"
              @ssl_protocol = kv.value
            when "trustcerts"
              @certs = get_file_path(kv.value)
            when "certspass"
              @certs_pass = kv.value
            when "tracessl"
              @trace_ssl = StringUtil.parse_bool(kv.value)
            else
              return false
            end
            return true
          end


          ######################################################
          # Implements Secure
          ######################################################

          def set_app_protocols(protocols)
            @app_protocols = protocols
            @sslctx.alpn_select_cb = lambda do |protocols|
                if protocols.include?("h2")
                  return "h2"
                elsif protocols.include?("http/1.1")
                  return "http/1.1"
                else
                  return protocols.first
                end
            end
          end

          def create_transporter(buf_size)
            SecureTransporter.new(@sslctx, true, buf_size, @trace_ssl)
          end

          def reload_cert()
            init_ssl()
          end

          def init_ssl()
            BayLog.debug("%s init ssl", self)
            @sslctx = SSL::SSLContext.new

            if @key_store == nil
              if @cert_file != nil
                @sslctx.cert = X509::Certificate.new(File.read(@cert_file))
              end
              if @key_file != nil
                @sslctx.key = PKey::RSA.new(File.read(@key_file))
              end
            else
              p12 = OpenSSL::PKCS12.new(File.read(@key_store), @key_store_pass)
              @sslctx.cert = p12.certificate
              @sslctx.key = p12.key
            end
          end


          private

          def get_file_path(file)
            if !File.absolute_path?(file)
              file = BayServer.bserv_home + "/" + file
            end

            if !File.file?(file)
              raise RuntimeError.new("File not found: #{file}")
            end

            file
          end

        end
      end
    end
  end
end
