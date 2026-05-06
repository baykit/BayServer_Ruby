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

        # All known names canonicalised to lowercase. Header name lookup
        # is case-insensitive per RFC 7230 and we already store every
        # entry lowercased, so emitting the lowercase form on the wire is
        # both spec-compliant and avoids a per-lookup String#downcase
        # allocation when callers pass these constants. The previous
        # mixed-case forms were the largest single source of
        # `String#downcase` in the alloc profile (Headers#get etc).
        CONTENT_TYPE = "content-type"
        CONTENT_LENGTH = "content-length"
        CONTENT_ENCODING = "content-encoding"
        HDR_TRANSFER_ENCODING = "transfer-encoding"
        CONNECTION = "connection"
        AUTHORIZATION = "authorization"
        WWW_AUTHENTICATE = "www-authenticate"
        STATUS = "status"
        LOCATION = "location"
        HOST = "host"
        COOKIE = "cookie"
        USER_AGENT = "user-agent"
        ACCEPT = "accept"
        ACCEPT_LANGUAGE = "accept-language"
        ACCEPT_ENCODING = "accept-encoding"
        UPGRADE_INSECURE_REQUESTS = "upgrade-insecure-requests"
        SERVER = "server"
        X_FORWARDED_HOST = "x-forwarded-host"
        X_FORWARDED_FOR = "x-forwarded-for"
        X_FORWARDED_PROTO = "x-forwarded-proto"
        X_FORWARDED_PORT = "x-forwarded-port"

        CONNECTION_CLOSE = 1
        CONNECTION_KEEP_ALIVE = 2
        CONNECTION_UPGRADE = 3
        CONNECTION_UNKNOWN = 4

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

        # `match?(/[A-Z]/)` returns a boolean without allocating a
        # MatchData (unlike `match`). When the name has no uppercase
        # bytes -- which is the case for every Headers::* constant and
        # for every name produced by the H1 header parser, since that
        # already lowercases bytes as it reads them -- we skip the
        # downcase. The fallback path keeps mixed-case external callers
        # working at the cost of an extra allocation only for them.
        def get(name)
          name = name.downcase if name.match?(/[A-Z]/)
          values = @headers[name]
          values ? values[0] : nil
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
          name = name.downcase if name.match?(/[A-Z]/)
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
          name = name.downcase if name.match?(/[A-Z]/)
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
          name = name.downcase if name.match?(/[A-Z]/)
          values = @headers[name]
          values ? values : []
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
          name = name.downcase if name.match?(/[A-Z]/)
          @headers.key?(name)
        end

        def remove(name)
          name = name.downcase if name.match?(/[A-Z]/)
          @headers.delete(name)
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
          return CONNECTION_UNKNOWN if con.nil?
          # casecmp? returns true/false without allocating, vs the
          # previous `con = con.downcase()` which always allocated even
          # when the value was already lowercase.
          if con.casecmp?("close")
            CONNECTION_CLOSE
          elsif con.casecmp?("keep-alive")
            CONNECTION_KEEP_ALIVE
          elsif con.casecmp?("upgrade")
            CONNECTION_UPGRADE
          else
            CONNECTION_UNKNOWN
          end
        end
      end
    end
  end
end