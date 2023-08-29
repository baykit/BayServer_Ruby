require 'baykit/bayserver/protocol/packet_unpacker'
require 'baykit/bayserver/util/simple_buffer'
require 'baykit/bayserver/agent/next_socket_action'


module Baykit
  module BayServer
    module Docker
      module Fcgi
        class FcgPacketUnPacker < Baykit::BayServer::Protocol::PacketUnPacker
          include Baykit::BayServer::Util
          include Baykit::BayServer::Agent

          attr :header_buf
          attr :data_buf

          attr :version
          attr :type
          attr :req_id
          attr :length
          attr :padding
          attr :padding_read_bytes

          STATE_REQD_PREAMBLE = 1  # #state for reading first 8 bytes (from version to reserved)
          STATE_READ_CONTENT = 2   #state for reading content data
          STATE_READ_PADDING = 3   # state for reading padding data
          STATE_END = 4            # End

          attr :state

          attr :cmd_unpacker
          attr :pkt_store
          attr :cont_len
          attr :read_bytes

          def initialize(pkt_store, cmd_unpacker)
            @cmd_unpacker = cmd_unpacker
            @pkt_store = pkt_store
            @header_buf = SimpleBuffer.new
            @data_buf = SimpleBuffer.new
            reset()
          end

          def reset
            @state = STATE_REQD_PREAMBLE
            @version = 0
            @type = nil
            @req_id = 0
            @length = 0
            @padding = 0
            @padding_read_bytes = 0
            @cont_len = 0
            @read_bytes = 0
            @header_buf.reset
            @data_buf.reset
          end

          def bytes_received(buf)
            next_suspend = false
            next_write = false
            pos = 0

            while pos < buf.length
              while @state != STATE_END && pos < buf.length

                case @state

                when STATE_REQD_PREAMBLE
                  # preamble read mode
                  len = FcgPacket::PREAMBLE_SIZE - @header_buf.length
                  if buf.length - pos < len
                    len = buf.length - pos
                  end

                  @header_buf.put(buf, pos, len)
                  pos += len

                  if @header_buf.length == FcgPacket::PREAMBLE_SIZE
                    header_read_done()
                    if @length == 0
                      if @padding == 0
                        change_state(STATE_END)
                      else
                        change_state(STATE_READ_PADDING)
                      end
                    else
                      change_state(STATE_READ_CONTENT)
                    end
                  end

                when STATE_READ_CONTENT
                  # content read mode
                  len = @length - @data_buf.length
                  if len > buf.length - pos
                    len = buf.length - pos
                  end

                  if len > 0
                    @data_buf.put(buf, pos, len)
                    pos += len

                    if @data_buf.length == @length
                      if @padding == 0
                        change_state(STATE_END)
                      else
                        change_state(STATE_READ_PADDING)
                      end
                    end
                  end

                when STATE_READ_PADDING
                  # padding read mode
                  len = @padding - @padding_read_bytes

                  if len > buf.length - pos
                    len = buf.length - pos
                  end

                  #@data_buf.put(buf, pos, len)
                  pos += len

                  if len > 0
                    @padding_read_bytes += len

                    if @padding_read_bytes == @padding
                      change_state(STATE_END)
                    end
                  end

                else
                  raise RuntimeError.new("IllegalState")
                end

              end

              if state == STATE_END
                pkt = @pkt_store.rent(@type)
                pkt.req_id = @req_id
                pkt.new_header_accessor.put_bytes(@header_buf.buf, 0, @header_buf.length)
                pkt.new_data_accessor.put_bytes(@data_buf.buf, 0, @data_buf.length)

                begin
                  state = @cmd_unpacker.packet_received(pkt)
                ensure
                  @pkt_store.Return(pkt)
                end

                reset()

                case state
                when NextSocketAction::SUSPEND
                  next_suspend = true
                when NextSocketAction::CONTINUE
                  nil
                when NextSocketAction::WRITE
                  next_write = true
                when NextSocketAction::CLOSE
                  return state
                end

              end
            end

            if next_write
              return NextSocketAction::WRITE
            elsif next_suspend
              return NextSocketAction::SUSPEND
            else
              return NextSocketAction::CONTINUE
            end
          end

          def change_state(new_state)
            @state = new_state
          end

          def header_read_done
            pre = @header_buf.buf.codepoints
            @version = byte_to_int(pre[0])
            @type = byte_to_int(pre[1])
            @req_id = bytes_to_int(pre[2], pre[3])
            @length = bytes_to_int(pre[4], pre[5])
            @padding = byte_to_int(pre[6])
            reserved = byte_to_int(pre[7])
            BayLog.debug("fcg: read packet header: version=%s type=%d reqId=%d length=%d padding=%d",
                          @version, @type, @req_id, @length, @padding)
          end

          def byte_to_int(b)
            return b & 0xff
          end

          def bytes_to_int(b1, b2)
            return byte_to_int(b1) << 8 | byte_to_int(b2)
          end

        end
      end
    end
  end
end
