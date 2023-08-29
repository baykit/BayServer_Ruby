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
        attr :packet_store
        attr :server_mode
        attr_accessor :ship

        def to_s()
          return ClassUtil.get_local_name(self.class) + " ship=" + ship.to_s
        end

        ##################################################
        # Implements Reusable
        ##################################################
        def reset()
          @command_unpacker.reset()
          @command_packer.reset()
          @packet_unpacker.reset()
          @packet_packer.reset()
        end

        ##################################################
        # Abstract methods
        ##################################################

        def protocol()
          raise NotImplementedError()
        end

        #
        # Get max of request data size (maybe not packet size)
        #
        def max_req_packet_data_size()
          raise NotImplementedError()
        end

        #
        # Get max of response data size (maybe not packet size)
        #
        def max_res_packet_data_size()
          raise NotImplementedError()
        end

        ##################################################
        # Other methods
        ##################################################
        def bytes_received(buf)
          return @packet_unpacker.bytes_received(buf)
        end
      end
    end
  end
end
