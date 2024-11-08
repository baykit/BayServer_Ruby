require 'baykit/bayserver/docker/http/h2/package'

#
#  HTTP/2 Window Update payload format
#
#  +-+-------------------------------------------------------------+
#  |R|              Window Size Increment (31)                     |
#  +-+-------------------------------------------------------------+
#

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module Command

            class CmdWindowUpdate < Baykit::BayServer::Docker::Http::H2::H2Command
              include Baykit::BayServer::Docker::Http::H2

              attr_accessor :window_size_increment

              def initialize(stream_id, flags=nil)
                super(H2Type::WINDOW_UPDATE, stream_id, flags)
              end

              def unpack(pkt)
                super
                acc = pkt.new_data_accessor()
                val = acc.get_int()
                @window_size_increment = H2Packet.extract_int31(val)
              end

              def pack(pkt)
                acc = pkt.new_data_accessor()
                acc.put_int(H2Packet.consolidate_flag_and_int32(0, @window_size_increment))
                BayLog.trace("h2: Pack windowUpdate size=#{@window_size_increment}")
                super
             end

              def handle(cmd_handler)
                return cmd_handler.handle_window_update(self)
              end
            end
          end
        end
      end
    end
  end
end


