require 'baykit/bayserver/docker/http/h2/package'

#
#  HTTP/2 Header payload format
#
#  +---------------+
#  |Pad Length? (8)|
#  +-+-------------+-----------------------------------------------+
#  |E|                 Stream Dependency? (31)                     |
#  +-+-------------+-----------------------------------------------+
#  |  Weight? (8)  |
#  +-+-------------+-----------------------------------------------+
#  |                   Header Block Fragment (*)                 ...
#  +---------------------------------------------------------------+
#  |                           Padding (*)                       ...
#  +---------------------------------------------------------------+
#
module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module Command

            class CmdHeaders < Baykit::BayServer::Docker::Http::H2::H2Command
              include Baykit::BayServer::Docker::Http::H2

              #
              # This class refers external byte array, so this IS NOT mutable
              #
              attr_accessor :start
              attr_accessor :length
              attr_accessor :data

              attr :pad_length
              attr_accessor :excluded
              attr :stream_dependency
              attr :weight
              attr :header_blocks

              def initialize(stream_id, flags=nil)
                super(H2Type::HEADERS, stream_id, flags)
                @pad_length = 0
                @excluded = false
                @stream_dependency = 0
                @weight = 0
                @header_blocks = []
              end

              def unpack(pkt)
                super
                acc = pkt.data_accessor

                if pkt.flags.padded?
                  @pad_length = acc.get_byte
                end
                if pkt.flags.priority?
                  val = acc.get_int
                  @excluded = H2Packet.extract_flag(val) == 1
                  @stream_dependency = H2Packet.extract_int31(val)
                  @weight = acc.get_byte
                  # RFC 7540 § 5.3.1: a stream MUST NOT depend on itself.
                  if @stream_dependency == stream_id
                    raise Baykit::BayServer::Protocol::ProtocolException.new("HEADERS stream depends on itself: #{stream_id}")
                  end
                end
                @data = pkt.buf
                @start = pkt.header_len + acc.pos
                @length = pkt.data_len - acc.pos - @pad_length

                # RFC 7540 § 6.2: padding length must leave at least one octet of payload.
                if @length < 0
                  raise Baykit::BayServer::Protocol::ProtocolException.new("HEADERS pad length exceeds payload: pad=#{@pad_length}")
                end
              end

              def pack(pkt)
                acc = pkt.data_accessor

                if @flags.padded?
                  acc.put_byte(@pad_length)
                end

                if @flags.priority?
                  acc.put_int(H2Packet.make_stream_dependency32(@excluded, @stream_dependency))
                  acc.put_byte(@weight)
                end

                acc.put_bytes(@data, @start, @length)
                super
              end

              def handle(cmd_handler)
                return cmd_handler.handle_headers(self)
              end

            end
          end
        end
      end
    end
  end
end


