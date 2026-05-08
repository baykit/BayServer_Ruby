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
                acc = pkt.data_accessor()
                preface_data = StringUtil.alloc(24)
                acc.get_bytes(preface_data, 0, 24)
                @protocol = preface_data[6, 8]
              end

              def pack(pkt)
                # The H2 client connection preface is 24 raw bytes that MUST appear
                # at the very start of the connection — it is NOT wrapped in an H2
                # frame (RFC 7540 § 3.5). H2Packet reserves FRAME_HEADER_LEN bytes
                # at buf[0..FRAME_HEADER_LEN] for the frame header; using
                # data_accessor here would produce 9 zero bytes followed by the
                # preface, which servers reject. Write the preface bytes directly
                # into the buffer from position 0 and set buf_len accordingly.
                while pkt.buf.length < PREFACE_BYTES.length
                  pkt.expand
                end
                pkt.buf[0, PREFACE_BYTES.length] = PREFACE_BYTES
                pkt.buf_len = PREFACE_BYTES.length
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


