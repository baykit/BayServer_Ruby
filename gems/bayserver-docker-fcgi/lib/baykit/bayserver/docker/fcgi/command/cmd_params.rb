require 'baykit/bayserver/docker/fcgi/fcg_command'
require 'baykit/bayserver/docker/fcgi/fcg_type'
require 'baykit/bayserver/util/string_util'

#
#  FCGI spec
#    http://www.mit.edu/~yandros/doc/specs/fcgi-spec.html
# 
# 
#  Params command format (Name-Value list)
# 
#          typedef struct {
#              unsigned char nameLengthB0;  // nameLengthB0  >> 7 == 0
#              unsigned char valueLengthB0; // valueLengthB0 >> 7 == 0
#              unsigned char nameData[nameLength];
#              unsigned char valueData[valueLength];
#          } FCGI_NameValuePair11;
# 
#          typedef struct {
#              unsigned char nameLengthB0;  // nameLengthB0  >> 7 == 0
#              unsigned char valueLengthB3; // valueLengthB3 >> 7 == 1
#              unsigned char valueLengthB2;
#              unsigned char valueLengthB1;
#              unsigned char valueLengthB0;
#              unsigned char nameData[nameLength];
#              unsigned char valueData[valueLength
#                      ((B3 & 0x7f) << 24) + (B2 << 16) + (B1 << 8) + B0];
#          } FCGI_NameValuePair14;
# 
#          typedef struct {
#              unsigned char nameLengthB3;  // nameLengthB3  >> 7 == 1
#              unsigned char nameLengthB2;
#              unsigned char nameLengthB1;
#              unsigned char nameLengthB0;
#              unsigned char valueLengthB0; // valueLengthB0 >> 7 == 0
#              unsigned char nameData[nameLength
#                      ((B3 & 0x7f) << 24) + (B2 << 16) + (B1 << 8) + B0];
#              unsigned char valueData[valueLength];
#          } FCGI_NameValuePair41;
# 
#          typedef struct {
#              unsigned char nameLengthB3;  // nameLengthB3  >> 7 == 1
#              unsigned char nameLengthB2;
#              unsigned char nameLengthB1;
#              unsigned char nameLengthB0;
#              unsigned char valueLengthB3; // valueLengthB3 >> 7 == 1
#              unsigned char valueLengthB2;
#              unsigned char valueLengthB1;
#              unsigned char valueLengthB0;
#              unsigned char nameData[nameLength
#                      ((B3 & 0x7f) << 24) + (B2 << 16) + (B1 << 8) + B0];
#              unsigned char valueData[valueLength
#                      ((B3 & 0x7f) << 24) + (B2 << 16) + (B1 << 8) + B0];
#          } FCGI_NameValuePair44;
# 

module Baykit
  module BayServer
    module Docker
      module Fcgi
        module Command
          class CmdParams < Baykit::BayServer::Docker::Fcgi::FcgCommand
            include Baykit::BayServer::Util

            attr :params

            def initialize(req_id)
              super(FcgType::PARAMS, req_id)
              @params = []
            end

            def unpack(pkt)
              super
              acc = pkt.new_data_accessor
              while acc.pos < pkt.data_len
                name_len = read_length(acc)
                value_len = read_length(acc)

                name = StringUtil.alloc(name_len)
                acc.get_bytes(name, 0, name_len)

                value = StringUtil.alloc(value_len)
                acc.get_bytes(value, 0, value_len)

                BayLog.trace("Params: %s=%s", name, value)
                add_param(name, value)
              end
            end

            def pack(pkt)
              acc = pkt.new_data_accessor
              @params.each do |nv|
                name = nv[0]
                value = nv[1]
                name_len = name.length
                value_len = value.length

                write_length(name_len, acc)
                write_length(value_len, acc)

                acc.put_string(name)
                acc.put_string(value)
              end

              # must be called from last line
              super
            end

            def handle(cmd_handler)
              return cmd_handler.handle_params(self)
            end


            def read_length(acc)
              len = acc.get_byte
              if len >> 7 == 0
                return len
              else
                len2 = acc.get_byte
                len3 = acc.get_byte
                len4 = acc.get_byte
                return ((len & 0x7f) << 24) | (len2 << 16) | (len3 << 8) | len4
              end
            end

            def write_length(len, acc)
              if len >> 7 == 0
                acc.put_byte(len)
              else
                len1 = (len >> 24 & 0xFF) | 0x80
                len2 = len >> 16 & 0xFF
                len3 = len >> 8 & 0xFF
                len4 = len & 0xFF
                buf = StringUtil.alloc(4)
                buf << len1 << len2 << len3 << len4
                acc.put_bytes(buf)
              end
            end

            def add_param(name, value)
              if name == nil
                raise RuntimeError.new("nil argument")
              end

              if value == nil
                value = ""
              end

              @params.append([name, value])
            end

            def to_s()
              "FcgCmdParams#{@params}"
            end
          end
        end
      end
    end
  end
end
