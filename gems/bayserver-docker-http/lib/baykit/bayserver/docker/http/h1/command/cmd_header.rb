require 'baykit/bayserver/docker/http/h1/command/package'
require 'baykit/bayserver/protocol/package'

#
# Header format
#
#        generic-message = start-line
#                           *(message-header CRLF)
#                           CRLF
#                           [ message-body ]
#        start-line      = Request-Line | Status-Line
#
#
#        message-header = field-name ":" [ field-value ]
#        field-name     = token
#        field-value    = *( field-content | LWS )
#        field-content  = <the OCTETs making up the field-value
#                         and consisting of either *TEXT or combinations
#                         of token, separators, and quoted-string>
#
module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          module Command

            class CmdHeader < Baykit::BayServer::Docker::Http::H1::H1Command
              include Baykit::BayServer::Protocol
              include Baykit::BayServer::Util

              STATE_READ_FIRST_LINE = 1
              STATE_READ_MESSAGE_HEADERS = 2

              CR_CODE_POINT = "\r".codepoints[0]
              LF_CODE_POINT = "\n".codepoints[0]
              SP_CODE_POINT = " ".codepoints[0]
              COLON_CODE_POINT = ":".codepoints[0]

              attr :headers
              attr :is_req_header  # request packet
              attr_accessor :method, :uri, :version
              attr_accessor :status

              def initialize(is_req_header)
                super(H1Type::HEADER)
                @headers = []
                @is_req_header = is_req_header
                @method = nil
                @uri = nil
                @version = nil
                @status = nil
              end

              def CmdHeader.new_req_header(method, uri, version)
                h = CmdHeader.new(true)
                h.method = method
                h.uri = uri
                h.version = version
                return h
              end

              def CmdHeader.new_res_header(headers, version)
                h = CmdHeader.new(false)
                h.version = version
                h.status = headers.status
                headers.names.each do |name|
                  headers.values(name).each do |value|
                    h.add_header name, value
                  end
                end
                return h
              end

              def add_header(name, value)
                if name == nil
                  raise Sink.new("name is nil")
                end
                if value == nil
                  BayLog.warn("Header value is nil: %s", name)
                  return
                end

                if !name.kind_of?(String)
                  BayLog.error("header name is not string: name=%s value=%s", name, value)
                  raise Sink.new("IllegalArgument")
                end
                if !value.kind_of?(String)
                  BayLog.error("header value is not string: name=%s value=%s", name, value)
                  raise Sink.new("IllegalArgument")
                end

                @headers.append([name, value])
              end

              def set_header(name, value)
                if name == nil
                  raise Sink.new("Nil")
                end
                if value == nil
                  BayLog.warn("Header value is null: %s", name)
                  return
                end

                if !name.kind_of?(String)
                  raise Sink.new("IllegalArgument")
                end
                if !value.kind_of?(String)
                  raise Sink.new("IllegalArgument")
                end

                @headers.each do |nv|
                  if nv[0].casecmp?(name)
                    nv[1] = value
                    return
                  end
                end

                headers.append([name, value])
              end

              def unpack(pkt)
                data_len = pkt.data_len()
                state = STATE_READ_FIRST_LINE

                line_start_pos = 0
                line_len = 0

                pos = 0
                while pos < data_len
                  next_nl = pkt.buf.index("\n", pos)
                  if !next_nl
                    # No more new lines
                    break
                  end

                  line_start_pos = pos

                  # Calculate line length excluding \n. Also strip a
                  # trailing \r if present. Using getbyte avoids the
                  # 1-char String allocation that `pkt.buf[next_nl-1]`
                  # used to make for every header line.
                  line_end = (next_nl > pos && pkt.buf.getbyte(next_nl - 1) == CR_CODE_POINT) ? next_nl - 1 : next_nl
                  line_len = line_end - pos

                  if line_len == 0
                    # Empty line found (End of headers)
                    # Move pos past the newline and exit
                    pos = next_nl + 1
                    break
                  end

                  if state == STATE_READ_FIRST_LINE
                    if @is_req_header
                      unpack_request_line(pkt.buf, pos, line_len)
                    else
                      unpack_status_line(pkt.buf, pos, line_len)
                    end

                    state = STATE_READ_MESSAGE_HEADERS
                  else
                    unpack_message_header(pkt.buf, pos, line_len)
                  end

                  # Move to the start of the next line
                  pos = next_nl + 1
                end

                if state == STATE_READ_FIRST_LINE
                  raise ProtocolException.new(
                    BayMessage.get(
                      :HTP_INVALID_HEADER_FORMAT,
                      pkt.buf[line_start_pos, line_len]))
                end
              end

              def pack(pkt)
                acc = pkt.data_accessor
                if @is_req_header
                  pack_request_line(acc)
                else
                  pack_status_line(acc)
                end

                @headers.each do |nv|
                  #@BayServer.debug "Packe header #{nv[0]}=#{nv[1]}"
                  pack_message_header(acc, nv[0], nv[1])
                end

                pack_end_header(acc)
                #BayLog.debug "#{self} pack header data header=#{pkt.header.length} bytes data=#{pkt.data.length} bytes"
                #BayLog.debug "#{self} pack header data: #{pkt.data.bytes}"
              end

              def handle(cmd_handler)
                return cmd_handler.handle_header(self)
              end

              def to_s
                "CommandHeader[H1]"
              end

              private
              # The previous implementation extracted the full line via
              # `buf[start, len]` and then `String#split` to break it
              # into three tokens; that allocated five strings (a copy
              # of the line, an Array, plus three split tokens) per
              # request. Since the buffer is already in hand, scanning
              # for the two space delimiters and taking three byteslice
              # results out of the original buffer needs only the three
              # field strings -- no whole-line copy, no Array.
              def unpack_request_line(buf, start, len)
                endp = start + len
                sp1 = buf.index(" ", start)
                if sp1.nil? || sp1 >= endp
                  raise ProtocolException.new(BayMessage.get(:HTP_INVALID_FIRST_LINE, buf.byteslice(start, len)))
                end
                sp2 = buf.index(" ", sp1 + 1)
                if sp2.nil? || sp2 >= endp
                  raise ProtocolException.new(BayMessage.get(:HTP_INVALID_FIRST_LINE, buf.byteslice(start, len)))
                end

                @method  = buf.byteslice(start, sp1 - start)
                @uri     = buf.byteslice(sp1 + 1, sp2 - sp1 - 1)
                @version = buf.byteslice(sp2 + 1, endp - sp2 - 1)
              end

              def unpack_status_line(buf, start, len)
                endp = start + len
                sp1 = buf.index(" ", start)
                if sp1.nil? || sp1 >= endp
                  raise ProtocolException.new BayMessage.get(:HTP_INVALID_FIRST_LINE, buf.byteslice(start, len))
                end

                @version = buf.byteslice(start, sp1 - start)
                # Status code is the next whitespace-delimited token. The
                # reason phrase that follows can contain spaces, so we
                # only need to find the first space after the code.
                sp2 = buf.index(" ", sp1 + 1)
                code_end = (sp2.nil? || sp2 > endp) ? endp : sp2
                @status = buf.byteslice(sp1 + 1, code_end - sp1 - 1).to_i
              end

              def unpack_message_header(bytes, start, len)
                # The previous loop walked `bytes[start + i]` byte by
                # byte; that returned a fresh 1-char String per index
                # and `b.downcase` allocated another per byte. The
                # allocation profile attributed ~9.7 % of all sampled
                # allocations to String#[] across the agent, with the
                # bulk of that coming from this single loop -- ~2 String
                # allocations per byte parsed, plus the per-byte concat
                # into `buf`. That work is unnecessary: getbyte returns
                # an Integer (no alloc), and once we know the colon
                # position we can take name and value as two byteslice
                # calls, lowercasing the name once for the whole slice.
                endp = start + len
                i = start
                # Skip leading whitespace before the header name.
                while i < endp && bytes.getbyte(i) == SP_CODE_POINT
                  i += 1
                end
                name_start = i
                colon = bytes.index(":", i)
                if colon.nil? || colon >= endp
                  raise ProtocolException.new BayMessage.get(:HTP_INVALID_HEADER_FORMAT, "")
                end
                name = bytes.byteslice(name_start, colon - name_start).downcase

                v_start = colon + 1
                while v_start < endp && bytes.getbyte(v_start) == SP_CODE_POINT
                  v_start += 1
                end
                value = bytes.byteslice(v_start, endp - v_start)

                add_header(name, value)

                #if(BayLog.trace_mode?)
                #  BayLog.trace("#{self} receive header: #{name}(#{name.length})=#{value}(#{value.length})")
                #end
              end

              def pack_request_line(acc)
                acc.put_bytes(@method)
                acc.put_bytes(" ")
                acc.put_bytes(@uri)
                acc.put_bytes(" ")
                acc.put_bytes(@version)
                acc.put_bytes(CharUtil::CRLF)
              end

              def pack_status_line(acc)
                desc = HttpStatus.description(@status)

                if version != nil && version.casecmp?("HTTP/1.1")
                  acc.put_bytes("HTTP/1.1")
                else
                  acc.put_bytes("HTTP/1.0")
                end

                # status
                acc.put_bytes(" ")
                acc.put_bytes(@status.to_s)
                acc.put_bytes(" ")
                acc.put_bytes(desc)
                acc.put_bytes(CharUtil::CRLF)
              end

              def pack_message_header(acc, name, value)
                if !name.kind_of?(String)
                  raise RuntimeError.new("IllegalArgument: #{name}")
                end
                if !value.kind_of?(String)
                  raise RuntimeError.new("IllegalArgument: #{value}")
                end
                acc.put_bytes(name)
                acc.put_bytes(":")
                acc.put_bytes(value)
                acc.put_bytes(CharUtil::CRLF)
              end

              def pack_end_header(acc)
                acc.put_bytes(CharUtil::CRLF)
              end
            end
          end
        end
      end
    end
  end
end


