require 'baykit/bayserver/docker/fcgi/fcg_command'
require 'baykit/bayserver/docker/fcgi/fcg_type'
require 'baykit/bayserver/docker/fcgi/fcg_packet'

#
#  FCGI spec
#    http://www.mit.edu/~yandros/doc/specs/fcgi-spec.html
# 
#  StdIn/StdOut/StdErr command format
#    raw data
#
module Baykit
  module BayServer
    module Docker
      module Fcgi
        module Command
          class InOutCommandBase < Baykit::BayServer::Docker::Fcgi::FcgCommand

            MAX_DATA_LEN = FcgPacket::MAXLEN - FcgPacket::PREAMBLE_SIZE

            #
            # This class refers external byte array, so this IS NOT mutable
            #
            attr :start
            attr :length
            attr :data

            def initialize(type, req_id, data=nil, start=0, len=0)
              super(type, req_id)
              @data = data
              @start = start
              @length = len
            end

            def unpack(pkt)
              super
              @start = pkt.header_len
              @length = pkt.data_len
              @data = pkt.buf
            end

            def pack(pkt)
              if @data != nil && @length > 0
                acc = pkt.new_data_accessor()
                acc.put_bytes(@data, @start, @length)
              end

              # must be called from last line
              super
            end

          end
        end
      end
    end
  end
end
