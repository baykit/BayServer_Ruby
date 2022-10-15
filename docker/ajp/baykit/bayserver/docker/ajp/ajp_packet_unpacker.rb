require 'baykit/bayserver/util/simple_buffer'
require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/protocol/packet_unpacker'

#
#  AJP Protocol
#  https://tomcat.apache.org/connectors-doc/ajp/ajpv13a.html
#
module Baykit
  module BayServer
    module Docker
      module Ajp
        class AjpPacketUnPacker < Baykit::BayServer::Protocol::PacketUnPacker

          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent

          attr :preamble_buf
          attr :body_buf

          STATE_READ_PREAMBLE = 1
          STATE_READ_BODY = 2
          STATE_END = 3

          attr :state

          attr :pkt_store
          attr :cmd_unpacker
          attr :body_len
          attr :read_bytes
          attr :type
          attr :to_server
          attr :need_data

          def initialize(pkt_store, cmd_unpacker)
            @pkt_store = pkt_store
            @cmd_unpacker = cmd_unpacker
            @preamble_buf = SimpleBuffer.new
            @body_buf = SimpleBuffer.new
            reset
          end

          def reset
            @state = STATE_READ_PREAMBLE
            @body_len = 0
            @read_bytes = 0
            @need_data = false
            @preamble_buf.reset
            @body_buf.reset
          end

          def bytes_received(buf)
            suspend = false
            pos = 0

            while pos < buf.length
              if @state == STATE_READ_PREAMBLE
                len = AjpPacket::PREAMBLE_SIZE - @preamble_buf.length
                if buf.length - pos < len
                  len = buf.length - pos
                end
                @preamble_buf.put(buf, pos, len)
                pos += len

                if @preamble_buf.length == AjpPacket::PREAMBLE_SIZE
                  preamble_read()
                  change_state(STATE_READ_BODY)
                end
              end

              if @state == STATE_READ_BODY
                len = @body_len - @body_buf.length
                if len > buf.length - pos
                  len = buf.length - pos
                end

                @body_buf.put(buf, pos, len)
                pos += len

                if @body_buf.length == @body_len
                  body_read()
                  change_state(STATE_END)
                end
              end

              if @state == STATE_END
                #BayLog.debug "AJP PacketUnpacker parse end: preamblelen=#{@preamble_buf.length} bodyLen=#{@body_buf.length}"

                pkt = @pkt_store.rent(@type)
                pkt.to_server = @to_server
                pkt.new_ajp_header_accessor.put_bytes(@preamble_buf.buf, 0, @preamble_buf.length)
                pkt.new_ajp_data_accessor.put_bytes(@body_buf.buf, 0, @body_buf.length)

                begin
                  next_action = @cmd_unpacker.packet_received(pkt)
                ensure
                  @pkt_store.Return(pkt)
                end
                reset
                @need_data = @cmd_unpacker.need_data

                if next_action == NextSocketAction::SUSPEND
                  suspend = true
                elsif next_action != NextSocketAction::CONTINUE
                  return next_action
                end
              end
            end

            #BayLog.debug("ajp: next action=read")
            if suspend
              return NextSocketAction::SUSPEND
            else
              return NextSocketAction::CONTINUE
            end
          end

          def change_state(new_state)
            @state = new_state
          end

          def preamble_read
            data = @preamble_buf.buf

            if data[0].codepoints[0] == 0x12 && data[1].codepoints[0] == 0x34
              @to_server = true
            elsif data[0] == 'A' && data[1] == 'B'
              @to_server = false
            else
              raise RuntimeError.new("Must be start with 0x1234 or 'AB'")
            end

            @body_len =  ((data[2].codepoints[0] << 8) | (data[3].codepoints[0] & 0xff)) & 0xffff
            BayLog.trace("ajp: read packet preamble: bodyLen=%d", @body_len)
          end

          def body_read()
            if @need_data
               @type = AjpType::DATA
            else
               @type =@body_buf.buf[0].codepoints[0] & 0xff
            end
          end

        end
      end
    end
  end
end

