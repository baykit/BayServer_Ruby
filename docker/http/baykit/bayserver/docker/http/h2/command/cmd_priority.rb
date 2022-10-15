require 'baykit/bayserver/docker/http/h2/package'

#
# HTTP/2 Priority payload format
#
#  +-+-------------------------------------------------------------+
#  |E|                  Stream Dependency (31)                     |
#  +-+-------------+-----------------------------------------------+
#  |   Weight (8)  |
#  +-+-------------+
#
#
module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module Command

            class CmdPriority < Baykit::BayServer::Docker::Http::H2::H2Command
              include Baykit::BayServer::Docker::Http::H2

              attr :weight
              attr :excluded
              attr :stream_dependency

              def initialize(stream_id, flags=nil)
                super(H2Type::PRIORITY, stream_id, flags)
              end

              def unpack(pkt)
                super
                acc = pkt.new_data_accessor()

                val = acc.get_int
                @excluded = H2Packet.extract_flag(val) == 1
                @stream_dependency = H2Packet.extract_int31(val)
                @weight = acc.get_byte
              end

              def pack(pkt)
                acc = pkt.new_data_accessor()
                acc.put_int(H2Packet.make_stream_dependency32(@excluded, @stream_dependency))
                acc.put_byte(@weight)
                super
             end

              def handle(cmd_handler)
                return cmd_handler.handle_priority(self)
              end
            end
          end
        end
      end
    end
  end
end


