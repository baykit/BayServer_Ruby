require 'baykit/bayserver/docker/http/h2/package'

require 'baykit/bayserver/util/string_util'

#
#  HTTP/2 GoAway payload format
#
#  +-+-------------------------------------------------------------+
#  |R|                  Last-Stream-ID (31)                        |
#  +-+-------------------------------------------------------------+
#  |                      Error Code (32)                          |
#  +---------------------------------------------------------------+
#  |                  Additional Debug Data (*)                    |
#  +---------------------------------------------------------------+
#
#
module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module Command

            class CmdGoAway < Baykit::BayServer::Docker::Http::H2::H2Command
              include Baykit::BayServer::Util
              include Baykit::BayServer::Docker::Http::H2

              attr_accessor :last_stream_id
              attr_accessor :error_code
              attr_accessor :debug_data
              
              def initialize(stream_id, flags=nil)
                super(H2Type::GOAWAY, stream_id, flags)
              end

              def unpack(pkt)
                super
                acc = pkt.new_data_accessor
                val = acc.get_int
                @last_stream_id = H2Packet.extract_int31(val)
                @error_code = acc.get_int
                @debug_data = StringUtil.alloc(pkt.data_len() - acc.pos)
                acc.get_bytes(@debug_data, 0, @debug_data.length)
              end

              def pack(pkt)
                acc = pkt.new_data_accessor()
                acc.put_int(@last_stream_id)
                acc.put_int(@error_code)
                if @debug_data != nil
                  acc.put_bytes(@debug_data, 0, @debug_data.length)
                end
                super
              end

              def handle(cmd_handler)
                return cmd_handler.handle_go_away(self)
              end
            end
          end
        end
      end
    end
  end
end


