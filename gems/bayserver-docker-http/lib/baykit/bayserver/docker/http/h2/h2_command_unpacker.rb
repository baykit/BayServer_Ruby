require 'baykit/bayserver/protocol/package'
require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/docker/http/h2/h2_type'
require 'baykit/bayserver/docker/http/h2/command/package'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2CommandUnPacker < Baykit::BayServer::Protocol::CommandUnPacker

            include Baykit::BayServer::Agent
            include Baykit::BayServer::Docker::Http::H2::Command

            # Subset of RFC 7540 §5.1 states tracked by the server. Idle is
            # represented by absence from @stream_states.
            STREAM_STATE_OPEN = :open
            STREAM_STATE_HALF_CLOSED_REMOTE = :half_closed_remote
            STREAM_STATE_CLOSED = :closed

            KNOWN_TYPES = [
              H2Type::PREFACE,
              H2Type::DATA,
              H2Type::HEADERS,
              H2Type::PRIORITY,
              H2Type::RST_STREAM,
              H2Type::SETTINGS,
              H2Type::PUSH_PROMISE,
              H2Type::PING,
              H2Type::GOAWAY,
              H2Type::WINDOW_UPDATE,
              H2Type::CONTINUATION,
            ].freeze

            attr :cmd_handler

            def initialize(cmd_handler)
              @cmd_handler = cmd_handler
              reset
            end

            def reset
              @in_header_block = false
              @header_block_stream_id = 0
              @pending_end_stream = false
              @stream_states = {}
              @highest_seen_stream_id = 0
            end

            def packet_received(pkt)
              BayLog.debug("h2: read packet type=%d strmid=%d len=%d flgs=%s", pkt.type, pkt.stream_id, pkt.data_len(), pkt.flags)

              type = pkt.type

              # RFC 7540 § 4.1: unknown frame types MUST be ignored and discarded.
              # Unknown types may appear inside a header block, in which case it is
              # still a PROTOCOL_ERROR because CONTINUATION must be the next frame.
              if !KNOWN_TYPES.include?(type)
                if @in_header_block
                  raise Baykit::BayServer::Protocol::ProtocolException.new("Unknown frame type #{type} during header block")
                end
                return NextSocketAction::CONTINUE
              end

              validate_frame(pkt)
              validate_stream_state(pkt)

              case type
              when H2Type::PREFACE
                cmd = CmdPreface.new(pkt.stream_id, pkt.flags)

              when H2Type::HEADERS
                cmd = CmdHeaders.new(pkt.stream_id, pkt.flags)

              when H2Type::PRIORITY
                cmd = CmdPriority.new(pkt.stream_id, pkt.flags)

              when H2Type::SETTINGS
                cmd = CmdSettings.new(pkt.stream_id, pkt.flags)

              when H2Type::WINDOW_UPDATE
                cmd = CmdWindowUpdate.new(pkt.stream_id, pkt.flags)

              when H2Type::DATA
                cmd = CmdData.new(pkt.stream_id, pkt.flags)

              when H2Type::GOAWAY
                cmd = CmdGoAway.new(pkt.stream_id, pkt.flags)

              when H2Type::PING
                cmd = CmdPing.new(pkt.stream_id, pkt.flags)

              when H2Type::RST_STREAM
                cmd = CmdRstStream.new(pkt.stream_id, pkt.flags)

              when H2Type::CONTINUATION
                cmd = CmdContinuation.new(pkt.stream_id, pkt.flags)

              when H2Type::PUSH_PROMISE
                # validateFrame raises ProtocolException for PUSH_PROMISE from client
                # but adding this here avoids nil cmd if ever reached.
                raise Baykit::BayServer::Protocol::ProtocolException.new("Server must not receive PUSH_PROMISE")

              else
                # Unreachable: KNOWN_TYPES guard above covers all cases.
                raise RuntimeError.new("Invalid Packet: #{pkt}")
              end

              update_header_block_state(pkt)
              update_stream_state(pkt)

              cmd.unpack pkt
              return cmd.handle(@cmd_handler)
            end

            private

            def validate_frame(pkt)
              type = pkt.type
              stream_id = pkt.stream_id
              flags = pkt.flags

              # RFC 7540 § 6.10: while a header block is being received, the next
              # frame MUST be a CONTINUATION on the same stream.
              if @in_header_block
                if type != H2Type::CONTINUATION
                  raise Baykit::BayServer::Protocol::ProtocolException.new(
                    "Expected CONTINUATION while in header block: got type=#{type}")
                end
                if stream_id != @header_block_stream_id
                  raise Baykit::BayServer::Protocol::ProtocolException.new(
                    "CONTINUATION on wrong stream: expected=#{@header_block_stream_id} got=#{stream_id}")
                end
              elsif type == H2Type::CONTINUATION
                # § 6.10: CONTINUATION outside a header block is PROTOCOL_ERROR.
                raise Baykit::BayServer::Protocol::ProtocolException.new("Unexpected CONTINUATION frame outside header block")
              end

              # RFC 7540 § 6.x: per-frame stream-id rules.
              case type
              when H2Type::DATA, H2Type::HEADERS, H2Type::PRIORITY,
                   H2Type::RST_STREAM, H2Type::PUSH_PROMISE, H2Type::CONTINUATION
                if stream_id == 0
                  raise Baykit::BayServer::Protocol::ProtocolException.new(
                    "Frame type #{type} requires non-zero stream id")
                end
              when H2Type::SETTINGS, H2Type::PING, H2Type::GOAWAY
                if stream_id != 0
                  raise Baykit::BayServer::Protocol::ProtocolException.new(
                    "Frame type #{type} requires stream id 0, got #{stream_id}")
                end
              # WindowUpdate: can be on stream 0 (connection) or a specific stream.
              end

              # RFC 7540 § 8.2: a server MUST NOT receive a PUSH_PROMISE frame.
              if type == H2Type::PUSH_PROMISE
                raise Baykit::BayServer::Protocol::ProtocolException.new("Server must not receive PUSH_PROMISE")
              end

              # RFC 7540 § 6.5: SETTINGS with ACK must have an empty payload.
              if type == H2Type::SETTINGS && flags.ack? && pkt.data_len() > 0
                raise Baykit::BayServer::Protocol::ProtocolException.new("SETTINGS ACK must have no payload")
              end
            end

            # RFC 7540 § 5.1: verify that the incoming frame is allowed in the current
            # stream state. Connection-level frames (stream id 0) are unaffected.
            # CONTINUATION is intentionally skipped here because its legality is
            # governed by the header-block rules checked in validate_frame.
            def validate_stream_state(pkt)
              type = pkt.type
              stream_id = pkt.stream_id
              return if stream_id == 0 || type == H2Type::CONTINUATION

              state = @stream_states[stream_id]

              if state == nil
                # "idle" — no state recorded yet for this stream id.
                implicitly_closed = stream_id <= @highest_seen_stream_id

                if type == H2Type::HEADERS
                  # RFC 7540 § 5.1.1: client streams must have odd ids and strictly increase.
                  if (stream_id & 1) == 0
                    raise Baykit::BayServer::Protocol::ProtocolException.new(
                      "Client HEADERS with even stream id #{stream_id}")
                  end
                  if implicitly_closed
                    raise Baykit::BayServer::Protocol::ProtocolException.new(
                      "Stream id #{stream_id} is not greater than the previous #{@highest_seen_stream_id}")
                  end
                  # Note: MAX_CONCURRENT_STREAMS enforcement intentionally omitted.
                  # See Ruby CLAUDE.md "Back out MAX_CONCURRENT_STREAMS enforcement".
                  return
                elsif type == H2Type::PRIORITY
                  return
                elsif type == H2Type::RST_STREAM || type == H2Type::DATA || type == H2Type::WINDOW_UPDATE
                  if implicitly_closed
                    raise Baykit::BayServer::Protocol::ProtocolException.new(
                      "Frame type #{type} on closed stream #{stream_id}")
                  end
                  raise Baykit::BayServer::Protocol::ProtocolException.new(
                    "Frame type #{type} on idle stream #{stream_id}")
                else
                  return
                end
              end

              case state
              when STREAM_STATE_OPEN
                # A second HEADERS on an open stream is a trailer section,
                # which § 8.1 requires to terminate the stream (END_STREAM).
                if type == H2Type::HEADERS && !pkt.flags.end_stream?
                  raise Baykit::BayServer::Protocol::ProtocolException.new(
                    "Trailer HEADERS on stream #{stream_id} missing END_STREAM")
                end

              when STREAM_STATE_HALF_CLOSED_REMOTE
                # Client has already sent END_STREAM. DATA/HEADERS from the
                # client is a stream error STREAM_CLOSED (§ 5.1).
                if type == H2Type::DATA || type == H2Type::HEADERS
                  raise Baykit::BayServer::Protocol::ProtocolException.new(
                    "Frame type #{type} on half-closed (remote) stream #{stream_id}")
                end

              when STREAM_STATE_CLOSED
                # A closed stream rejects everything except PRIORITY and
                # WINDOW_UPDATE (the latter may still be in-flight).
                if type != H2Type::PRIORITY && type != H2Type::WINDOW_UPDATE
                  raise Baykit::BayServer::Protocol::ProtocolException.new(
                    "Frame type #{type} on closed stream #{stream_id}")
                end
              end
            end

            def update_header_block_state(pkt)
              type = pkt.type
              if type == H2Type::HEADERS || type == H2Type::PUSH_PROMISE
                @in_header_block = !pkt.flags.end_headers?
                @header_block_stream_id = pkt.stream_id
                @pending_end_stream = pkt.flags.end_stream?
              elsif type == H2Type::CONTINUATION
                if pkt.flags.end_headers?
                  @in_header_block = false
                end
              end
            end

            # Transition the stream state machine based on the incoming frame.
            # Called after validate_stream_state has accepted the frame.
            def update_stream_state(pkt)
              type = pkt.type
              stream_id = pkt.stream_id
              return if stream_id == 0

              state = @stream_states[stream_id]

              case type
              when H2Type::HEADERS
                if state == nil
                  # Opening a new stream implicitly closes any lower-id streams.
                  if stream_id > @highest_seen_stream_id
                    @highest_seen_stream_id = stream_id
                  end
                  state = STREAM_STATE_OPEN
                  @stream_states[stream_id] = state
                  if pkt.flags.end_headers? && pkt.flags.end_stream?
                    @stream_states[stream_id] = STREAM_STATE_HALF_CLOSED_REMOTE
                  end
                elsif state == STREAM_STATE_OPEN
                  # Trailer section: END_STREAM required.
                  if pkt.flags.end_headers? && pkt.flags.end_stream?
                    @stream_states[stream_id] = STREAM_STATE_HALF_CLOSED_REMOTE
                  end
                end

              when H2Type::CONTINUATION
                # The HEADERS' END_STREAM takes effect once the header block
                # closes via END_HEADERS on this CONTINUATION.
                if pkt.flags.end_headers? && @pending_end_stream && state == STREAM_STATE_OPEN
                  @stream_states[stream_id] = STREAM_STATE_HALF_CLOSED_REMOTE
                end
                if pkt.flags.end_headers?
                  @pending_end_stream = false
                end

              when H2Type::DATA
                if pkt.flags.end_stream? && state == STREAM_STATE_OPEN
                  @stream_states[stream_id] = STREAM_STATE_HALF_CLOSED_REMOTE
                end

              when H2Type::RST_STREAM
                @stream_states[stream_id] = STREAM_STATE_CLOSED
                if stream_id > @highest_seen_stream_id
                  @highest_seen_stream_id = stream_id
                end
              end
            end

          end
        end
      end
    end
  end
end


