require 'date'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Util
      class CgiUtil

        REQUEST_METHOD = "REQUEST_METHOD"
        REQUEST_URI = "REQUEST_URI"
        SERVER_PROTOCOL = "SERVER_PROTOCOL"
        GATEWAY_INTERFACE = "GATEWAY_INTERFACE"
        SERVER_NAME = "SERVER_NAME"
        SERVER_PORT = "SERVER_PORT"
        QUERY_STRING = "QUERY_STRING"
        SCRIPT_NAME = "SCRIPT_NAME"
        SCRIPT_FILENAME = "SCRIPT_FILENAME"
        PATH_TRANSLATED = "PATH_TRANSLATED"
        PATH_INFO = "PATH_INFO"
        CONTENT_TYPE = "CONTENT_TYPE"
        CONTENT_LENGTH = "CONTENT_LENGTH"
        REMOTE_ADDR = "REMOTE_ADDR"
        REMOTE_PORT = "REMOTE_PORT"
        REMOTE_USER = "REMOTE_USER"
        HTTP_ACCEPT = "HTTP_ACCEPT"
        HTTP_COOKIE = "HTTP_COOKIE"
        HTTP_HOST = "HTTP_HOST"
        HTTP_USER_AGENT = "HTTP_USER_AGENT"
        HTTP_ACCEPT_ENCODING = "HTTP_ACCEPT_ENCODING"
        HTTP_ACCEPT_LANGUAGE = "HTTP_ACCEPT_LANGUAGE"
        HTTP_CONNECTION = "HTTP_CONNECTION"
        HTTP_UPGRADE_INSECURE_REQUESTS = "HTTP_UPGRADE_INSECURE_REQUESTS"
        HTTPS = "HTTPS"
        PATH = "PATH"
        SERVER_SIGNATURE = "SERVER_SIGNATURE"
        SERVER_SOFTWARE = "SERVER_SOFTWARE"
        SERVER_ADDR = "SERVER_ADDR"
        DOCUMENT_ROOT = "DOCUMENT_ROOT"
        REQUEST_SCHEME = "REQUEST_SCHEME"
        CONTEXT_PREFIX = "CONTEXT_PREFIX"
        CONTEXT_DOCUMENT_ROOT = "CONTEXT_DOCUMENT_ROOT"
        SERVER_ADMIN = "SERVER_ADMIN"
        REQUEST_TIME_FLOAT = "REQUEST_TIME_FLOAT"
        REQUEST_TIME = "REQUEST_TIME"
        UNIQUE_ID = "UNIQUE_ID"
        X_FORWARDED_HOST = "X_FORWARDED_HOST"
        X_FORWARDED_FOR = "X_FORWARDED_FOR"
        X_FORWARDED_PROTO = "X_FORWARDED_PROTO"
        X_FORWARDED_PORT = "X_FORWARDED_PORT"

        def self.get_env_hash(path, doc_root, script_base, tur)
          map = {}
          get_env(path, doc_root, script_base, tur) do |name, value|
            map[name] = value
          end
          map
        end


        def self.get_env(path, doc_root, script_base, tur, &block)

          req_headers = tur.req.headers

          ctype = req_headers.content_type
          if StringUtil.set? ctype
            pos = ctype.index("charset=")
            if pos != nil && pos >= 0
              tur.req.charset = ctype[pos+8 .. -1].strip
            end
          end

          add_env(REQUEST_METHOD, tur.req.method, &block)
          add_env(REQUEST_URI, tur.req.uri, &block)
          add_env(SERVER_PROTOCOL, tur.req.protocol, &block)
          add_env(GATEWAY_INTERFACE, "CGI/1.1", &block)

          add_env(SERVER_NAME, tur.req.req_host, &block)
          add_env(SERVER_ADDR, tur.req.server_address, &block)
          if tur.req.req_port >= 0
            add_env(SERVER_PORT, tur.req.req_port, &block)
          end

          add_env(SERVER_SOFTWARE, BayServer.get_software_name, &block)
          add_env(CONTEXT_DOCUMENT_ROOT, doc_root, &block)

          tur.req.headers.names.each do |name|
            newval = nil
            tur.req.headers.values(name).each do |value|
              if newval == nil
                newval = value
              else
                newval = newval + "; " + value
              end
            end

            name = name.upcase.tr('-', '_')
            if name.start_with?("X_FORWARDED_")
              add_env(name, newval, &block)
            else
              case name
              when CONTENT_TYPE, CONTENT_LENGTH
                add_env(name, newval, &block)
              else
                add_env("HTTP_" + name, newval, &block)
              end
            end
          end

          add_env(REMOTE_ADDR, tur.req.remote_address, &block)
          add_env(REMOTE_PORT, tur.req.remote_port, &block)
          #add_env(REMOTE_USER, "unknown")

          add_env(REQUEST_SCHEME, tur.is_secure ? "https": "http", &block)
          tmp_secure = tur.is_secure
          fproto = tur.req.headers.get(Headers::X_FORWARDED_PROTO)
          if fproto != nil
            tmp_secure = fproto.casecmp?("https")
          end
          if tmp_secure
            add_env(HTTPS, "on", &block)
          end

          add_env(QUERY_STRING, tur.req.query_string, &block)
          add_env(SCRIPT_NAME, tur.req.script_name, &block)
          add_env(UNIQUE_ID, DateTime.now.to_s, &block)

          if tur.req.path_info == nil
            add_env(PATH_INFO, "", &block)
          else
            add_env(PATH_INFO, tur.req.path_info, &block)

            locpath = doc_root
            if locpath.end_with? "/"
              locpath = locpath[0 .. -2]
            end

            path_translated = locpath + tur.req.path_info
            add_env(PATH_TRANSLATED, path_translated, &block)
          end

          if !script_base.end_with?("/")
            script_base = script_base + "/"
          end

          add_env(SCRIPT_FILENAME, "#{script_base}#{tur.req.script_name[path.length .. -1]}", &block)
          add_env(PATH, ENV["PATH"], &block)
        end

        private
        def self.add_env(key, value)
          if value == nil
            value = ""
          end
          
          # Handles null terminated string
          value = value.to_s.split("\0")[0]
          if value == nil
            value = ""
          end

          yield(key, value.to_s)
        end 
      end
    end
  end
end
