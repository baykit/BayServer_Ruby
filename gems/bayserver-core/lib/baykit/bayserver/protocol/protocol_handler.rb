require 'baykit/bayserver/util/class_util'

module Baykit
  module BayServer
    module Protocol
      class ProtocolHandler
        include Baykit::BayServer::Util::Reusable # implements

        include Baykit::BayServer::Util

        attr :packet_unpacker
        attr :packet_packer
        attr :command_unpacker
        attr :command_packer
        attr :command_handler
        attr :server_mode
        attr_accessor :ship

        def initialize(pkt_unpacker, pkt_packer, cmd_unpacker, cmd_packer, cmd_handler, svr_mode)
          @packet_unpacker = pkt_unpacker
          @packet_packer = pkt_packer
          @command_unpacker = cmd_unpacker
          @command_packer = cmd_packer
          @command_handler  = cmd_handler
          @server_mode = svr_mode
        end
        def to_s()
          return ClassUtil.get_local_name(self.class) + " ship=" + ship.to_s
        end

        def init(sip)
          @ship = sip
        end

        ##################################################
        # Implements Reusable
        ##################################################
        def reset()
          @command_unpacker.reset
          @command_packer.reset
          @packet_unpacker.reset
          @packet_packer.reset
          @command_handler.reset
          @ship = nil
        end

        ##################################################
        # Abstract methods
        ##################################################

        def protocol()
          raise NotImplementedError.new
        end

        #
        # Get max of request data size (maybe not packet size)
        #
        def max_req_packet_data_size()
          raise NotImplementedError.new
        end

        #
        # Get max of response data size (maybe not packet size)
        #
        def max_res_packet_data_size()
          raise NotImplementedError.new
        end

        ##################################################
        # Other methods
        ##################################################
        def bytes_received(buf)
          return @packet_unpacker.bytes_received(buf)
        end

        def post(cmd, &lis)
          @command_packer.post(@ship, cmd, &lis)
        end
      end
    end
  end
end
