require 'baykit/bayserver/docker/http/h2/package'
require 'baykit/bayserver/util/string_util'

#
#
#  Preface is dummy command and packet
#
#    packet is not in frame format but raw data: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
#
module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module Command

            class CmdPreface < Baykit::BayServer::Docker::Http::H2::H2Command
              include Baykit::BayServer::Docker::Http::H2
              include Baykit::BayServer::Util

              PREFACE_BYTES = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
              attr :protocol

              def initialize(stream_id, flags=nil)
                super(H2Type::PREFACE, stream_id, flags)
              end

              def unpack(pkt)
                acc = pkt.new_data_accessor()
                preface_data = StringUtil.alloc(24)
                acc.get_bytes(preface_data, 0, 24)
                @protocol = preface_data[6, 8]
              end

              def pack(pkt)
                acc = pkt.new_h2_data_accessor()
                acc.put_bytes(PREFACE_BYTES)
              end

              def handle(cmd_handler)
                return cmd_handler.handle_preface(self)
              end
            end
          end
        end
      end
    end
  end
end


