require 'baykit/bayserver/docker/ajp/ajp_command'
require 'baykit/bayserver/docker/ajp/ajp_type'
require 'baykit/bayserver/docker/ajp/ajp_packet'
require 'baykit/bayserver/util/string_util'
#
#  Send body chunk format
#
#  AJP13_SEND_BODY_CHUNK :=
#    prefix_code   (byte) 0x03
#    chunk_length  (integer)
#    chunk         *(byte)
#
module Baykit
  module BayServer
    module Docker
      module Ajp
        module Command
          class CmdSendBodyChunk < Baykit::BayServer::Docker::Ajp::AjpCommand
            include Baykit::BayServer::Docker::Ajp
            include Baykit::BayServer::Util

            attr :chunk
            attr :offset
            attr :length

            MAX_CHUNKLEN = AjpPacket::MAX_DATA_LEN - 4

            def initialize(buf, ofs, len)
              super(AjpType::SEND_BODY_CHUNK, false)
              @chunk = buf
              @offset = ofs
              @length = len
            end

            def pack(pkt) 
              if @length > MAX_CHUNKLEN
                raise RuntimeError.new("IllegalArgument")
              end 
              
              acc = pkt.new_ajp_data_accessor
              acc.put_byte(@type)
              acc.put_short(@length)
              acc.put_bytes(@chunk, @offset, @length)
              acc.put_byte(0)   # maybe document bug

              #  must be called from last line
              super
            end

            def unpack(pkt)
              acc = pkt.new_ajp_data_accessor
              acc.get_byte   # code
              @length = acc.get_short
              if @chunk == nil || @length > @chunk.length
                @chunk = StringUtil.alloc(@length)
              end

              acc.get_bytes(@chunk, 0, @length)
            end

            def handle(handler)
              return handler.handle_send_body_chunk(self)
            end

          end
        end
      end
    end
  end
end

