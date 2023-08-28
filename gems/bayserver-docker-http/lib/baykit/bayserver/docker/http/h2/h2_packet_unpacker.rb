require 'baykit/bayserver/protocol/packet_unpacker'
require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/util/simple_buffer'


module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2PacketUnPacker < Baykit::BayServer::Protocol::PacketUnPacker

            include Baykit::BayServer::Agent
            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Docker::Http
            include Baykit::BayServer::Util

            class FrameHeaderItem
              attr :start
              attr :len
              attr_accessor :pos

              def initialize(start, len)
                @start = start
                @len = len
                @pos = 0
              end

              def get(buf, index)
                return buf.buf[@start + index].codepoints[0]
              end
            end

            STATE_READ_LENGTH = 1
            STATE_READ_TYPE = 2
            STATE_READ_FLAGS = 3
            STATE_READ_STREAM_IDENTIFIER = 4
            STATE_READ_FLAME_PAYLOAD = 5
            STATE_END = 6

            FRAME_LEN_LENGTH = 3
            FRAME_LEN_TYPE = 1
            FRAME_LEN_FLAGS = 1
            FRAME_LEN_STREAM_IDENTIFIER = 4

            FLAGS_END_STREAM = 0x1
            FLAGS_END_HEADERS = 0x4
            FLAGS_PADDED = 0x8
            FLAGS_PRIORITY = 0x20

            CONNECTION_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

            attr :state
            attr :tmp_buf
            attr :item
            attr :preface_read
            attr :type
            attr :payload_len
            attr :flags
            attr :stream_id

            attr :cmd_unpacker
            attr :pkt_store
            attr :server_mode

            attr :cont_len
            attr :read_bytes
            attr :pos

            def initialize(cmd_unpacker, pkt_store, server_mode)
              @cmd_unpacker = cmd_unpacker
              @pkt_store = pkt_store
              @server_mode = server_mode
              @tmp_buf = SimpleBuffer.new
              reset
            end

            def reset()
              reset_state()
              @preface_read = false
            end

            def reset_state()
              change_state STATE_READ_LENGTH
              @item = FrameHeaderItem.new(0, FRAME_LEN_LENGTH)
              @cont_len = 0
              @read_bytes = 0
              @tmp_buf.reset
              @type = nil
              @flags = 0
              @stream_id = 0
              @payload_len = 0
            end

            def bytes_received(buf)
              suspend = false

              @pos = 0
              if @server_mode && !@preface_read
                len = CONNECTION_PREFACE.length - @tmp_buf.length
                if len > buf.length
                  len = buf.length
                end
                @tmp_buf.put(buf, @pos, len)
                @pos += len
                if @tmp_buf.length == CONNECTION_PREFACE.length
                  @tmp_buf.length.times do |i|
                    if CONNECTION_PREFACE[i] != @tmp_buf.buf[i]
                      raise ProtocolException.new "Invalid connection preface: #{@tmp_buf.bytes[0, @tmp_buf.length]}"
                    end
                  end
                  pkt = @pkt_store.rent(H2Type::PREFACE)
                  pkt.new_data_accessor().put_bytes(@tmp_buf.buf, 0, @tmp_buf.length)
                  nstat = @cmd_unpacker.packet_received(pkt)
                  @pkt_store.Return(pkt)
                  if nstat != NextSocketAction::CONTINUE
                    return nstat
                  end

                  BayLog.debug("h2: Connection preface OK")
                  @preface_read = true
                  @tmp_buf.reset()
                end
              end

              while @state != STATE_END && pos < buf.length
                case @state
                when STATE_READ_LENGTH
                  if read_header_item(buf)
                    @payload_len = ((@item.get(@tmp_buf, 0) & 0xFF) << 16 |
                                    (@item.get(@tmp_buf, 1) & 0xFF) << 8 |
                                    (@item.get(@tmp_buf, 2) & 0xFF))
                    @item = FrameHeaderItem.new(@tmp_buf.length, FRAME_LEN_TYPE)
                    change_state STATE_READ_TYPE
                  end

                when STATE_READ_TYPE
                  if read_header_item(buf)
                    @type = @item.get(@tmp_buf, 0)
                    @item = FrameHeaderItem.new(@tmp_buf.length, FRAME_LEN_FLAGS)
                    change_state STATE_READ_FLAGS
                  end

                when STATE_READ_FLAGS
                  if read_header_item(buf)
                    @flags = @item.get(@tmp_buf, 0)
                    @item = FrameHeaderItem.new(@tmp_buf.length, FRAME_LEN_STREAM_IDENTIFIER)
                    change_state STATE_READ_STREAM_IDENTIFIER
                  end

                when STATE_READ_STREAM_IDENTIFIER
                  if read_header_item(buf)
                    @stream_id =
                      ((@item.get(@tmp_buf, 0) & 0x7F) << 24) |
                        (@item.get(@tmp_buf, 1) << 16) |
                        (@item.get(@tmp_buf, 2) << 8) |
                        @item.get(@tmp_buf, 3)

                    @item = FrameHeaderItem.new(@tmp_buf.length, @payload_len)
                    change_state STATE_READ_FLAME_PAYLOAD
                  end

                when STATE_READ_FLAME_PAYLOAD
                  if read_header_item(buf)
                    change_state STATE_END
                  end

                else
                  raise RuntimeError.new "Illegal State"

                end

                if @state == STATE_END
                  pkt = @pkt_store.rent(@type)
                  pkt.stream_id = @stream_id
                  pkt.flags = H2Flags.new(@flags)
                  pkt.new_header_accessor().put_bytes(@tmp_buf.buf, 0, H2Packet::FRAME_HEADER_LEN)
                  pkt.new_data_accessor().put_bytes(@tmp_buf.buf, H2Packet::FRAME_HEADER_LEN, @tmp_buf.length - H2Packet::FRAME_HEADER_LEN)

                  begin
                    next_act = @cmd_unpacker.packet_received(pkt)
                  ensure
                    @pkt_store.Return(pkt)
                    reset_state()
                  end

                  if next_act == NextSocketAction::SUSPEND
                    suspend = true
                  elsif next_act != NextSocketAction::CONTINUE
                    return next_act
                  end
                end
              end

              if suspend
                return NextSocketAction::SUSPEND
              else
                return NextSocketAction::CONTINUE
              end
            end

            private
            def read_header_item(buf)
              len = @item.len - @item.pos
              if buf.length - @pos < len
                len = buf.length - @pos
              end
              @tmp_buf.put(buf, @pos, len)
              @pos += len
              @item.pos += len

              return @item.pos == @item.len
            end

            def change_state new_state
              @state = new_state
            end
          end
        end
      end
    end
  end
end

