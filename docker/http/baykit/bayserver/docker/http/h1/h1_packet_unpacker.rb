require 'baykit/bayserver/protocol/packet_unpacker'
require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/agent/upgrade_exception'
require 'baykit/bayserver/util/simple_buffer'

#    HTTP/1.x has no packet format. So we make HTTP header and content pretend to be packet
#
#    From RFC2616
#    generic-message : start-line
#                      (message-header CRLF)*
#                       CRLF
#                       [message-body]
#
#
#
module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          class H1PacketUnPacker < Baykit::BayServer::Protocol::PacketUnPacker

            include Baykit::BayServer::Agent
            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Docker::Http
            include Baykit::BayServer::Util

            STATE_READ_HEADERS = 1
            STATE_READ_CONTENT = 2
            STATE_END = 3

            MAX_LINE_LEN = 8192

            attr :state
            attr :cmd_upacker
            attr :pkt_store
            attr :tmp_buf

            def initialize(cmd_upacker, pkt_store)
              @cmd_upacker = cmd_upacker
              @pkt_store = pkt_store
              @tmp_buf = SimpleBuffer.new()
              reset_state()
            end

            ######################################################
            # implements Reusable
            ######################################################

            def reset()
              reset_state()
            end

            ######################################################
            # Other methods
            ######################################################

            def bytes_received(buf)
              if @state == STATE_END
                reset
                raise RuntimeError.new("IllegalState")
              end

              BayLog.debug("H1: bytes_received len=%d", buf.length)
              pos = 0
              buf_start = 0
              line_len = 0
              if @state == STATE_READ_HEADERS
                while pos < buf.length
                  b = buf[pos]
                  @tmp_buf.put_byte(b)
                  pos += 1
                  #@BayServer.info b + " " + b.codepoints[0].to_s + " pos=" + pos.to_s
                  if b == CharUtil::CR
                    next
                  elsif b == CharUtil::LF
                    if line_len == 0
                      # empty line (all headers are read)
                      pkt = @pkt_store.rent(H1Type::HEADER)
                      pkt.new_data_accessor.put_bytes(@tmp_buf.bytes, 0, @tmp_buf.length)

                      begin
                        next_act = @cmd_upacker.packet_received(pkt)
                      ensure
                        @pkt_store.Return pkt
                      end

                      case next_act
                      when NextSocketAction::CONTINUE, NextSocketAction::SUSPEND
                        if @cmd_upacker.finished()
                          change_state(STATE_END)
                        else
                          change_state(STATE_READ_CONTENT)
                        end
                      when NextSocketAction::CLOSE
                        # Maybe error
                        reset_state()
                        return next_act
                      else
                        raise RuntimeError.new("Invalid next action: #{next_act}")
                      end

                      break
                    end
                    line_len = 0
                  else
                    line_len += 1
                  end
                  if line_len >= MAX_LINE_LEN
                    raise ProtocolException.new("Http/1 Line is too long")
                  end
                end
              end

              suspend = false
              if @state == STATE_READ_CONTENT
                while pos < buf.length
                  pkt = @pkt_store.rent(H1Type::CONTENT)

                  len = buf.length - pos
                  if len > H1Packet::MAX_DATA_LEN
                    len = H1Packet::MAX_DATA_LEN
                  end

                  #BayLog.debug("remain=#{buf.length - pos} len=#{len}")
                  pkt.new_data_accessor.put_bytes(buf, pos, len)
                  pos += len

                  begin
                    next_act = @cmd_upacker.packet_received(pkt)
                  ensure
                    @pkt_store.Return(pkt)
                  end

                  case next_act
                  when NextSocketAction::CONTINUE
                    if @cmd_upacker.finished()
                      change_state(STATE_END)
                    end
                  when NextSocketAction::SUSPEND
                    suspend = true
                  when NextSocketAction::CLOSE
                    reset_state
                    return next_act
                  end
                end
              end

              if @state == STATE_END
                reset_state()
              end

              if suspend
                BayLog.debug("%s read suspend", self)
                return NextSocketAction::SUSPEND
              else
                return NextSocketAction::CONTINUE
              end

            end

            private

            def change_state new_state
              @state = new_state
            end

            def reset_state
              change_state STATE_READ_HEADERS
              @tmp_buf.reset()
            end
          end
        end
      end
    end
  end
end

