require 'baykit/bayserver/docker/http/h2/h2_flags'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2Command < Baykit::BayServer::Protocol::Command
            include Baykit::BayServer::Docker::Http
            include Baykit::BayServer::Docker::Http::H2

            attr :flags
            attr_accessor :stream_id

            def initialize(type, stream_id, flags=nil)
              super type
              @stream_id = stream_id
              if flags == nil
                @flags = H2Flags.new
              else
                @flags = flags
              end
            end

            def unpack(pkt)
              @stream_id = pkt.stream_id
              @flags = pkt.flags
            end

            def pack(pkt)
              pkt.stream_id = @stream_id
              pkt.flags = @flags
              pkt.pack_header
            end
          end
        end
      end
    end
  end
end


