require 'baykit/bayserver/docker/ajp/ajp_command'
require 'baykit/bayserver/docker/ajp/ajp_type'
require 'baykit/bayserver/docker/ajp/ajp_packet'

#
#  Data command format
#
#  AJP13_DATA :=
#    len, raw data
#
module Baykit
  module BayServer
    module Docker
      module Ajp
        module Command
          class CmdData < Baykit::BayServer::Docker::Ajp::AjpCommand
            LENGTH_OF_SIZE = 2
            MAX_DATA_LEN = AjpPacket::MAX_DATA_LEN - LENGTH_OF_SIZE

            attr :start
            attr_accessor :length
            attr_accessor :data

            def initialize(data = nil, start = 0, length = 0)
              super(AjpType::DATA, true)
              @data = data
              @start = start
              @length = length
            end

            def unpack(pkt)
              super
              acc = pkt.new_ajp_data_accessor
              @length = acc.get_short
              @data = pkt.buf
              @start = pkt.header_len + 2
            end

            def pack(pkt)
              acc = pkt.new_ajp_data_accessor
              acc.put_short(@length)
              acc.put_bytes(@data, @start, @length)

              #BayLog.debug "pack AJP command data: #{pkt.data.bytes}"

              #  must be called from last line
              super
            end

            def handle(handler)
              return handler.handle_data(self)
            end
          end
        end
      end
    end
  end
end

