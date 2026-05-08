require 'baykit/bayserver/docker/http/h2/package'

#
#
module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module Command

            class CmdPing < Baykit::BayServer::Docker::Http::H2::H2Command
              include Baykit::BayServer::Docker::Http::H2

              attr :opaque_data

              def initialize(stream_id, flags=nil, opaque_data=nil)
                super(H2Type::PING, stream_id, flags)
                # RFC 7540 § 6.7: echo the received opaque_data back; the
                # constructor previously always allocated zeros and dropped it.
                @opaque_data = (opaque_data != nil) ? opaque_data : [0, 0, 0, 0, 0, 0, 0, 0].pack("C*")
              end

              def unpack(pkt)
                super
                acc = pkt.data_accessor()

                acc.get_bytes(@opaque_data, 0, 8)
              end

              def pack(pkt)
                acc = pkt.data_accessor()
                acc.put_bytes(@opaque_data)
                super
              end

              def handle(cmd_handler)
                return cmd_handler.handle_ping(self)
              end
            end
          end
        end
      end
    end
  end
end


