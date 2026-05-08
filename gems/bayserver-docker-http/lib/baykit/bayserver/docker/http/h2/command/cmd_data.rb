require 'baykit/bayserver/docker/http/h2/package'

#
# HTTP/2 Data payload format
#
# +---------------+
# |Pad Length? (8)|
# +---------------+-----------------------------------------------+
# |                            Data (*)                         ...
# +---------------------------------------------------------------+
# |                           Padding (*)                       ...
# +---------------------------------------------------------------+
#
module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module Command

            class CmdData < Baykit::BayServer::Docker::Http::H2::H2Command
              include Baykit::BayServer::Docker::Http::H2

              #
              # This class refers external byte array, so this IS NOT mutable
              #
              attr :start
              attr :length
              attr :data

              def initialize(stream_id, flags, data=nil, start=nil, len=nil)
                super(H2Type::DATA, stream_id, flags)
                @data = data
                @start = start
                @length = len
              end

              def unpack(pkt)
                super
                acc = pkt.data_accessor()

                pad_length = 0
                if pkt.flags.padded?
                  pad_length = acc.get_byte
                end

                @data = pkt.buf
                @start = pkt.header_len + acc.pos
                @length = pkt.data_len() - acc.pos - pad_length

                # RFC 7540 § 6.1: padding length must leave at least one octet of data.
                if @length < 0
                  raise Baykit::BayServer::Protocol::ProtocolException.new("DATA pad length exceeds payload: pad=#{pad_length}")
                end
              end

              def pack(pkt)
                acc = pkt.data_accessor()
                if @flags.padded?
                  raise RuntimeError.new("Padding not supported")
                end
                acc.put_bytes(@data, @start, @length)
                super
              end

              def handle(cmd_handler)
                return cmd_handler.handle_data(self)
              end
            end
          end
        end
      end
    end
  end
end


