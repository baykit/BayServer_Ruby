require 'baykit/bayserver/protocol/protocol_exception'

require 'baykit/bayserver/docker/http/h2/package'

#
#  HTTP/2 Setting payload format
#
#  +-------------------------------+
#  |       Identifier (16)         |
#  +-------------------------------+-------------------------------+
#  |                        Value (32)                             |
#  +---------------------------------------------------------------+
#
#
module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module Command

            class CmdSettings < Baykit::BayServer::Docker::Http::H2::H2Command
              include Baykit::BayServer::Protocol
              include Baykit::BayServer::Docker::Http::H2

              class Item
                attr :id
                attr :value

                def initialize(id, value)
                  @id = id
                  @value = value
                end
              end

              HEADER_TABLE_SIZE = 0x1
              ENABLE_PUSH = 0x2
              MAX_CONCURRENT_STREAMS = 0x3
              INITIAL_WINDOW_SIZE = 0x4
              MAX_FRAME_SIZE = 0x5
              MAX_HEADER_LIST_SIZE = 0x6

              INIT_HEADER_TABLE_SIZE = 4096
              INIT_ENABLE_PUSH = 1
              INIT_MAX_CONCURRENT_STREAMS = -1
              INIT_INITIAL_WINDOW_SIZE = 65535
              INIT_MAX_FRAME_SIZE = 16384
              INIT_MAX_HEADER_LIST_SIZE = -1

              attr :items

              def initialize(stream_id, flags=nil)
                super(H2Type::SETTINGS, stream_id, flags)
                @items = []
              end

              def unpack(pkt)
                super
                if @flags.ack?
                  return
                end

                acc = pkt.new_data_accessor()
                pos = 0
                while pos < pkt.data_len()
                  id = acc.get_short()
                  value = acc.get_int()
                  @items.append(Item.new(id, value))
                  pos += 6
                end
              end

              def pack(pkt)
                if @flags.ack?
                  # do not pack payload
                else
                  acc = pkt.new_data_accessor()
                  @items.each do |item|
                    acc.put_short(item.id)
                    acc.put_int(item.value)
                  end
                end
                super
              end

              def handle(cmd_handler)
                return cmd_handler.handle_settings(self)
              end

            end
          end
        end
      end
    end
  end
end


