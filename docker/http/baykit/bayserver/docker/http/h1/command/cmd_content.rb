require 'baykit/bayserver/docker/http/h1/h1_command'

module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          module Command

            class CmdContent < Baykit::BayServer::Docker::Http::H1::H1Command

              attr :buf
              attr :start
              attr :len

              def initialize(buf = nil, start = nil, len = nil)
                super(H1Type::CONTENT)
                @buf = buf
                @start = start
                @len = len
              end

              def unpack(pkt)
                @buf = pkt.buf
                @start = pkt.header_len
                @len = pkt.data_len()
              end

              def pack(pkt)
                acc = pkt.new_data_accessor
                acc.put_bytes(@buf, @start, @len)
              end

              def handle(cmd_handler)
                return cmd_handler.handle_content(self)
              end

            end
          end
        end
      end
    end
  end
end


