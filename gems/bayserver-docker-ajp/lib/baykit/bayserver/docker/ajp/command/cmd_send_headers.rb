require 'baykit/bayserver/docker/ajp/ajp_command'
require 'baykit/bayserver/docker/ajp/ajp_type'
require 'baykit/bayserver/util/http_status'

#
#  Send headers format
#
#  AJP13_SEND_HEADERS :=
#    prefix_code       4
#    http_status_code  (integer)
#    http_status_msg   (string)
#    num_headers       (integer)
#    response_headers *(res_header_name header_value)
#
#  res_header_name :=
#      sc_res_header_name | (string)   [see below for how this is parsed]
#
#  sc_res_header_name := 0xA0 (byte)
#
#  header_value := (string)
#
module Baykit
  module BayServer
    module Docker
      module Ajp
        module Command
          class CmdSendHeaders < Baykit::BayServer::Docker::Ajp::AjpCommand
            include Baykit::BayServer::Util

            class << self 
              attr :well_known_header_map
            end
            
            @well_known_header_map = {
              "content-type" => 0xA001,
              "content-language" => 0xA002,
              "content-length" => 0xA003,
              "date" => 0xA004,
              "last-modified" => 0xA005,
              "location" => 0xA006,
              "set-cookie" => 0xA007,
              "set-cookie2" => 0xA008,
              "servlet-engine" => 0xA009,
              "status" => 0xA00A,
              "www-authenticate" => 0xA00B,
            }

            def self.get_well_known_header_name(code)
              @well_known_header_map.keys.each do |name|
                if @well_known_header_map[name] == code
                  return name
                end
              end
              return nil
            end

            attr :headers
            attr_accessor :status
            attr :desc

            def initialize
              super(AjpType::SEND_HEADERS, false)
              @headers = {}
              @status = HttpStatus::OK
              @desc = nil
            end

            def to_s()
              return "SendHeaders(s=#{@status} d=#{@desc} h=#{@headers}"
            end

            def pack(pkt) 
              acc = pkt.new_ajp_data_accessor
              acc.put_byte(@type)
              acc.put_short(@status)
              acc.put_string(HttpStatus.description(@status))

              count = 0
              @headers.keys.each do |key|
                count += @headers[key].length
              end
              acc.put_short(count)

              @headers.keys.each do |name|
                code = CmdSendHeaders.well_known_header_map[name]

                @headers[name].each do |value|
                  if code != nil
                    acc.put_short(code)
                  else
                    acc.put_string(name)
                  end
                  acc.put_string(value)
                end
              end

              #  must be called from last line
              super
            end

            def unpack(pkt) 
              acc = pkt.new_ajp_data_accessor
              prefix_code = acc.get_byte
              if prefix_code != AjpType::SEND_HEADERS
                raise ProtocolException.new "Expected SEND_HEADERS"
              end

              @status = acc.get_short
              @desc = acc.get_string
              count = acc.get_short
              count.times do |i|
                code = acc.get_short
                name = CmdSendHeaders.get_well_known_header_name(code)
                if name == nil
                  name = acc.get_string_by_len(code)
                end

                value = acc.get_string
                add_header(name, value)
              end
              #BayLog.info("%s", self)
            end

            def handle(handler)
              return handler.handle_send_headers(self)
            end


            def get_header(name)
              values = @headers[name.downcase]
              if values == nil || values.empty?
                nil
              else
                values[0]
              end
            end

            def add_header(name, value)
              values = @headers[name]
              if values == nil
                values = []
                @headers[name] = values
              end
              values.append(value)
            end

          end
        end
      end
    end
  end
end

