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
                acc = pkt.new_data_accessor
                data_len = pkt.data_len()
                state = STATE_READ_FIRST_LINE

                line_start_pos = 0
                line_len = 0

                data_len.times do |pos|
                  b = acc.get_byte
                  case b
                  when CharUtil::CR_BYTE
                    next

                  when CharUtil::LF_BYTE
                    if line_len == 0
                      break
                    end
                    if state == STATE_READ_FIRST_LINE
                      if @is_req_header
                        unpack_request_line(pkt.buf, line_start_pos, line_len)
                      else
                        unpack_status_line(pkt.buf, line_start_pos, line_len)
                      end

                      state = STATE_READ_MESSAGE_HEADERS
                    else
                      unpack_message_header(pkt.buf, line_start_pos, line_len)
                    end

                    line_len = 0
                    line_start_pos = pos + 1

                  else
                    line_len += 1
                  end

                end

                if state == STATE_READ_FIRST_LINE
                  raise ProtocolException.new(
                    BayMessage.get(
                      :HTP_INVALID_HEADER_FORMAT,
                      pkt.buf[line_start_pos, line_len]))
                end
              end

              def pack(pkt)
                acc = pkt.new_data_accessor
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
              def unpack_request_line (buf, start, len)
                line = buf[start, len]
                items = line.split(" ")
                if items.length != 3
                  raise ProtocolException.new(BayMessage.get(:HTP_INVALID_FIRST_LINE, line))
                end

                @method = items[0]
                @uri = items[1]
                @version = items[2]
              end

              def unpack_status_line(buf, start, len)
                line = buf[start, len]
                items = line.split(" ")

                if items.length < 2
                  raise ProtocolException.new BayMessage.get(:HTP_INVALID_FIRST_LINE, line)
                end

                @version = items[0]
                @status = items[1].to_i
              end

              def unpack_message_header(bytes, start, len)
                buf = ""
                read_name = true
                name = nil
                skipping = true

                len.times do |i|
                  b = bytes[start + i]
                  if skipping && b == ' '
                    next
                  elsif read_name && b == ":"
                    # header name completed
                    name = buf
                    buf = ""
                    skipping = true
                    read_name = false
                  else
                    if read_name
                      # make the case of header name be lower force
                      buf.concat(b.downcase)
                    else
                      # header value
                      buf.concat(b)
                    end
                    skipping = false
                  end
                end

                if name == nil
                  raise ProtocolException.new BayMessage.get(:HTP_INVALID_HEADER_FORMAT, "")
                end

                value = buf

                add_header(name, value)

                #if(BayLog.trace_mode?)
                #  BayLog.trace("#{self} receive header: #{name}(#{name.length})=#{value}(#{value.length})")
                #end
              end

              def pack_request_line(acc)
                acc.put_string(@method)
                acc.put_bytes(" ")
                acc.put_string(@uri)
                acc.put_bytes(" ")
                acc.put_string(@version);
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
                acc.put_string(@status.to_s)
                acc.put_bytes(" ")
                acc.put_string(desc)
                acc.put_bytes(CharUtil::CRLF)
              end

              def pack_message_header(acc, name, value)
                if !name.kind_of?(String)
                  raise RuntimeError.new("IllegalArgument: #{name}")
                end
                if !value.kind_of?(String)
                  raise RuntimeError.new("IllegalArgument: #{value}")
                end
                acc.put_string(name)
                acc.put_bytes(":")
                acc.put_string(value)
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


