require 'baykit/bayserver/docker/ajp/ajp_command'
require 'baykit/bayserver/docker/ajp/ajp_type'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/util/headers'

#
#  AJP protocol
#     https://tomcat.apache.org/connectors-doc/ajp/ajpv13a.html
# 
#  AJP13_FORWARD_REQUEST :=
#      prefix_code      (byte) 0x02 = JK_AJP13_FORWARD_REQUEST
#      method           (byte)
#      protocol         (string)
#      req_uri          (string)
#      remote_addr      (string)
#      remote_host      (string)
#      server_name      (string)
#      server_port      (integer)
#      is_ssl           (boolean)
#      num_headers      (integer)
#      request_headers(req_header_name req_header_value)
#      attributes     (attribut_name attribute_value)
#      request_terminator (byte) OxFF
#
module Baykit
  module BayServer
    module Docker
      module Ajp
        module Command
          class CmdForwardRequest < Baykit::BayServer::Docker::Ajp::AjpCommand
            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Util

            class << self
              attr :method_map
              attr :well_known_header_map
              attr :attribute_name_map
            end

            @method_map = {
              1 => "OPTIONS",
              2 => "GET",
              3 => "HEAD",
              4 => "POST",
              5 => "PUT",
              6 => "DELETE",
              7 => "TRACE",
              8 => "PROPFIND",
              9 => "PROPPATCH",
              10 => "MKCOL",
              11 => "COPY",
              12 => "MOVE",
              13 => "LOCK",
              14 => "UNLOCK",
              15 => "ACL",
              16 => "REPORT",
              17 => "VERSION_CONTROL",
              18 => "CHECKIN",
              19 => "CHECKOUT",
              20 => "UNCHECKOUT",
              21 => "SEARCH",
              22 => "MKWORKSPACE",
              23 => "UPDATE",
              24 => "LABEL",
              25 => "MERGE",
              26 => "BASELINE_CONTROL",
              27 => "MKACTIVITY",
            }

            def self.get_method_code(method)
              @method_map.keys.each do |key|
                if @method_map[key].casecmp? method
                  return key
                end
              end
              return -1
            end


            @well_known_header_map =  {
              0xA001 => "Accept",
              0xA002 => "Accept-Charset",
              0xA003 => "Accept-Encoding",
              0xA004 => "Accept-Language",
              0xA005 => "Authorization",
              0xA006 => "Connection",
              0xA007 => "Content-Type",
              0xA008 => "Content-Length",
              0xA009 => "Cookie",
              0xA00A => "Cookie2",
              0xA00B => "Host",
              0xA00C => "Pragma",
              0xA00D => "Referer",
              0xA00E => "User-Agent",
            }

            def self.get_well_known_header_code(name)
              @well_known_header_map.keys.each do |key|
                if @well_known_header_map[key].casecmp? name
                  return key
                end
              end
              return -1
            end


            @attribute_name_map = {
              0x01 => "?context",
              0x02 => "?servlet_path",
              0x03 => "?remote_user",
              0x04 => "?auth_type",
              0x05 => "?query_string",
              0x06 => "?route",
              0x07 => "?ssl_cert",
              0x08 => "?ssl_cipher",
              0x09 => "?ssl_session",
              0x0A => "?req_attribute",
              0x0B => "?ssl_key_size",
              0x0C => "?secret",
              0x0D => "?stored_method",
            }

            def self.get_attribute_code(atr)
              @attribute_name_map.keys.each do |key|
                if @attribute_name_map[key].casecmp?(atr)
                  return key
                end
              end
              return -1
            end

            attr_accessor :method
            attr_accessor :protocol
            attr_accessor :req_uri
            attr_accessor :remote_addr
            attr_accessor :remote_host
            attr_accessor :server_name
            attr_accessor :server_port
            attr_accessor :is_ssl
            attr_accessor :headers
            attr :attributes

            def initialize
              super(AjpType::FORWARD_REQUEST, true)
              @headers = Headers.new()
              @attributes = {}
            end

            def to_s()
              return "ForwardRequest(m=#{self.method} p=#{self.protocol} u=#{self.req_uri} ra=#{self.remote_addr} rh=#{self.remote_host} sn=#{self.server_name} sp=#{self.server_port} ss=#{self.is_ssl} h=#{self.headers}"
            end

            def pack(pkt)
              #BayLog.info("%s", self)
              acc = pkt.new_ajp_data_accessor()
              acc.put_byte(@type) # prefix code
              code = CmdForwardRequest.get_method_code(@method)
              if code <= 0
                raise ProtocolException.new "Invalid method: #{@method}"
              end
              acc.put_byte(code)
              acc.put_string(@protocol)
              acc.put_string(@req_uri)
              acc.put_string(@remote_addr)
              acc.put_string(@remote_host)
              acc.put_string(@server_name)
              acc.put_short(@server_port)
              acc.put_byte(@is_ssl ? 1 : 0)
              write_request_headers(acc)
              write_attributes(acc)

              #  must be called from last line
              super
            end

            def unpack(pkt) 
              super
              acc = pkt.new_ajp_data_accessor()
              acc.get_byte() # prefix code
              code = acc.get_byte
              @method = CmdForwardRequest.method_map[code]
              if @method == nil
                raise ProtocolException.new "Invalid method code: #{code}"
              end
              @protocol = acc.get_string
              @req_uri = acc.get_string
              @remote_addr = acc.get_string
              @remote_host = acc.get_string
              @server_name = acc.get_string
              @server_port = acc.get_short
              @is_ssl = acc.get_byte == 1

              read_request_headers(acc)
              read_attributes(acc)
            end

            def handle(handler)
              return handler.handle_forward_request(self)
            end


            private
            def read_request_headers(acc)
              count = acc.get_short
              count.times do |i|
                code = acc.get_short

                if code >= 0xA000
                  name = CmdForwardRequest.well_known_header_map[code]

                  if name == nil
                    raise ProtocolException.new("Invalid header")
                  end
                else
                  # code is length of header name
                  name = acc.get_string_by_len(code)
                end

                value = acc.get_string
                @headers.add(name, value)
                #BayLog.trace "ForwardRequest header: #{name}=#{value}"
              end
            end

            def read_attributes(acc)
              while true
                code = acc.get_byte()

                if code == 0xFF
                  break
                elsif code == 0x0A
                  name = acc.get_string()
                else
                  name = CmdForwardRequest.attribute_name_map[code]
                  if name == nil
                    raise ProtocolException.new "Invalid attribute: code=#{code}"
                  end
                end

                if code == 0x0B # "?ssl_key_size"
                  value = acc.get_short()
                  @attributes[name] = value.to_s
                else
                  value = acc.get_string
                  @attributes[name] = value
                end

                #BayLog.trace "ForwardRequest readAttributes:#{name}=#{value}"
              end
            end

            def write_request_headers(acc)
              h_list = []
              @headers.names.each do |name|
                @headers.values(name).each do |value|
                  h_list << [name, value]
                end
              end
              
              acc.put_short(h_list.length)
              h_list.each do |item|
                code = CmdForwardRequest.get_well_known_header_code(item[0])
                if code != -1
                  acc.put_short(code)
                else 
                  acc.put_string(item[0])
                end
                
                acc.put_string(item[1])
              end

            end

            def write_attributes(acc)
              @attributes.keys.each do |name|
                value = @attributes[name]
                code = CmdForwardRequest.get_attribute_code(name)
                if code != -1
                  acc.put_byte(code)
                else
                  acc.put_string(name)
                end

                acc.put_string(value)
              end

              acc.put_byte(0xFF) # terminator code
            end
          end

        end
      end
    end
  end
end

