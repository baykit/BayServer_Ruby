require 'baykit/bayserver/util/http_status'

module Baykit
  module BayServer
    module Util
      class Headers
        include Baykit::BayServer::Util

        # 
        # known header names
        #
        HEADER_SEPARATOR = ": "

        CONTENT_TYPE = "content-type"
        CONTENT_LENGTH = "content-length"
        CONTENT_ENCODING = "content-encoding"
        HDR_TRANSFER_ENCODING = "Transfer-Encoding"
        CONNECTION = "Connection"
        AUTHORIZATION = "Authorization"
        WWW_AUTHENTICATE = "WWW-Authenticate"
        STATUS = "Status"
        LOCATION = "Location"
        HOST = "Host"
        COOKIE = "Cookie"
        USER_AGENT = "User-Agent"
        ACCEPT = "Accept"
        ACCEPT_LANGUAGE = "Accept-Language"
        ACCEPT_ENCODING = "Accept-Encoding"
        UPGRADE_INSECURE_REQUESTS = "Upgrade-Insecure-Requests"
        SERVER = "Server"
        X_FORWARDED_HOST = "X-Forwarded-Host"
        X_FORWARDED_FOR = "X-Forwarded-For"
        X_FORWARDED_PROTO = "X-Forwarded-Proto"
        X_FORWARDED_PORT = "X-Forwarded-Port"

        CONNECTION_CLOSE = 1
        CONNECTION_KEEP_ALIVE = 2
        CONNECTION_UPGRADE = 3
        CONNECTION_UNKOWN = 4

        attr :status
        attr :headers


        def initialize
          @headers = {}
          clear()
        end

        def to_s()
          return "Header(s=#{@status.to_s} h=#{@headers}"
        end


        def clear()
          @headers.clear()
          @status = HttpStatus::OK
        end

        def copy_to(dst)
          dst.status = @status
          @headers.keys.each do |name|
            values = @headers[name].dup
            dst.headers[name] = values
          end
        end

        def status= (new_val)
          @status = new_val.to_i
        end

        def get(name)
          values = headers[name.downcase()]
          if(values == nil)
            return nil
          else
            return values[0]
          end
        end

        def get_int(name)
          val = get(name)
          if(val == nil)
            return -1
          else
            return val.to_i
          end
        end

        def set(name, value)
          name = name.downcase
          values = @headers[name]
          if(values == nil)
            values = []
            @headers[name] = values
          end
          values.clear()
          values.append(value)
        end


        def set_int(name, value)
          set(name, value.to_s)
        end

        def add(name, value)
          name = name.downcase()
          values = @headers[name]
          if(values == nil)
            values = []
            @headers[name] = values
          end
          values.append(value)
        end

        def add_int(name, value)
          add(name, value.to_s)
        end

        def names()
          return @headers.keys()
        end

        def values(name)
          values = @headers[name.downcase()]
          if(values == nil)
            return []
          else
            return values
          end
        end

        def count()
          c = 0
          @headers.keys.each do |name|
            @headers[name].each do |value|
              c += 1
            end
          end
          return c
        end

        def contains(name)
          return @headers.keys.include?(name.downcase())
        end

        def remove(name)
          @headers.delete(name.downcase())
        end

        #
        # Utility methods
        #
        def content_type()
          return get(CONTENT_TYPE)
        end

        def set_content_type(type)
          set(CONTENT_TYPE, type)
        end

        def content_length()
          length = get(CONTENT_LENGTH)
          if(StringUtil.empty?(length))
            return -1
          else
            return Integer(length)
          end
        end

        def set_content_length(len)
          set_int(CONTENT_LENGTH, len)
        end

        def get_connection
          con = get(CONNECTION)
          if(con != nil)
            con = con.downcase()
          end
          case con
          when "close" then
            return CONNECTION_CLOSE
          when "keep-alive" then
            return CONNECTION_KEEP_ALIVE
          when "upgrade" then
            return CONNECTION_UPGRADE
          else
            return CONNECTION_UNKOWN
          end
        end
      end
    end
  end
end