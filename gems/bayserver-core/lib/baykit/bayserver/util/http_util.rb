require 'base64'
require 'resolv'

require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/char_util'
require 'baykit/bayserver/util/headers'
require 'baykit/bayserver/util/http_util'
require 'baykit/bayserver/protocol/protocol_exception'

module Baykit
  module BayServer
    module Util
      class HttpUtil
        include Baykit::BayServer::Util
        include Baykit::BayServer::Protocol

        MAX_LINE_LEN = 5000

        def HttpUtil.read_line(file)
          # Current reading line
          buf = StringUtil.alloc(MAX_LINE_LEN)

          n = 0
          eof = false
          while true
            begin
              c = file.readchar
            rescue EOFError => e
              eof = true
              break
            end

            # If line is too long, return error
            if n >= MAX_LINE_LEN
              raise RuntimeError.new("Request line too long")
            end
            # If character is newline, end to read line
            if c == CharUtil::LF
              break
            end

            # Put the character to buffer
            buf.concat(c)
            n += 1
          end

          if n == 0 && eof
            return nil
          else
            return buf.chomp
          end
        end

        #
        # Parse message headers
        #   message-header = field-name &quot;:&quot; [field-value]
        #
        def HttpUtil.parse_message_headers(file, header)
          while true
            line = read_line(file)

            #  if line is empty ("\r\n")
            #  finish reading.
            if StringUtil.empty?(line)
              break
            end

            pos = line.index ":"
            if pos != nil
              key = line[0 .. pos - 1].strip
              val = line[pos + 1 .. -1].strip
              header.add(key, val)
            end
          end
        end

        #
        # Send MIME headers This method is called from send_headers
        #
        def HttpUtil.send_mime_headers(headers, buf)

          headers.names.each do |name|
            headers.values(name).each do |value|
              buf.put(name)
              buf.put(Headers::HEADER_SEPARATOR)
              buf.put(value)
              send_new_line(buf)
            end
          end
        end

        def HttpUtil.send_new_line(buf)
          buf.put(CharUtil::CRLF)
        end

        def HttpUtil.parse_authorization(tur)
          auth = tur.req.headers.get(Headers::AUTHORIZATION)
          if StringUtil.set?(auth)
            ptn = /Basic (.*)/
            mch = auth.match(ptn)
            if !mch
              BayLog.warn("Not matched with basic authentication format")
            else
              auth = mch[1]

              auth = Base64.decode64(auth)
              ptn = /(.*):(.*)/
              mch = auth.match(ptn)
              if mch
                tur.req.remote_user = mch[1]
                tur.req.remote_pass = mch[2]
              end
            end
          end
        end


        def HttpUtil.parse_host_port(tur, default_port)
          tur.req.req_host = ""

          host_port = tur.req.headers.get(Headers::X_FORWARDED_HOST)
          if StringUtil.set?(host_port)
            tur.req.headers.remove(Headers::X_FORWARDED_HOST)
            tur.req.headers.set(Headers::HOST, host_port)
          end

          host_port = tur.req.headers.get(Headers::HOST)

          if StringUtil.set?(host_port)
            pos = host_port.rindex(':')
            if pos == nil
              tur.req.req_host = host_port
              tur.req.req_port = default_port
            else
              tur.req.req_host = host_port[0, pos]
              begin
                tur.req.req_port = host_port[pos + 1 .. -1].to_i
              rescue => e
                BayLog.error(e)
              end
            end
          end
        end

        def HttpUtil.resolve_remote_host(adr)
          if adr == nil
            return nil
          end
          begin
            return Resolv.getname(adr)
          rescue => e
            BayLog.warn_e(e, "Cannot get remote host name: %s", e)
            return nil
          end
        end

        def HttpUtil.check_uri(uri)
          if uri.include?("\x00")
            raise ProtocolException, "path contains null byte"
          end

          if uri.each_char.any? { |ch| (ch.ord < 0x20) || (ch.ord == 0x7f) }
            raise ProtocolException, "path contains control character"
          end
        end
      end
    end
  end
end
