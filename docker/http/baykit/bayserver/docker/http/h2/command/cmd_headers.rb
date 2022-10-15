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
                acc = pkt.new_h2_data_accessor

                if pkt.flags.padded?
                  @pad_length = acc.get_byte
                end
                if pkt.flags.priority?
                  val = acc.get_int
                  @excluded = H2Packet.extract_flag(val) == 1
                  @stream_dependency = H2Packet.extract_int31(val)
                  @weight = acc.get_byte
                end
                read_header_block(acc, pkt.data_len())
              end

              def pack(pkt)
                acc = pkt.new_h2_data_accessor

                if @flags.padded?
                  acc.put_byte(@pad_length)
                end

                if @flags.priority?
                  acc.put_int(H2Packet.make_stream_dependency32(@excluded, @stream_dependency))
                  acc.put_byte(@weight)
                end
                write_header_block(acc)
                super
              end

              def handle(cmd_handler)
                return cmd_handler.handle_headers(self)
              end

              def read_header_block(acc, len)
                while acc.pos < len
                  blk = HeaderBlock.unpack(acc)
                  #if(BayLog.trace_mode?)
                  #  BayLog.trace "h2: Read header block: #{blk}"
                  #end
                  @header_blocks << blk
                end
              end

              def write_header_block(acc)
                @header_blocks.each do |blk|
                  #if(BayLog.trace_mode?)
                  #  BayLog.trace "h2: Write header block: #{blk}"
                  #end
                  HeaderBlock.pack(blk, acc)
                end
              end

              def add_header_block(blk)
                @header_blocks.append(blk)
              end
            end
          end
        end
      end
    end
  end
end


