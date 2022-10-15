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
                @data = pkt.buf
                @start = pkt.header_len
                @length = pkt.data_len()
              end

              def pack(pkt)
                acc = pkt.new_data_accessor()
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


