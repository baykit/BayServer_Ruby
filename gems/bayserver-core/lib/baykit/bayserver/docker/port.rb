require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Port
        include Docker  # implements

        def protocol
          raise NotImplementedError.new
        end

        def host
          raise NotImplementedError.new
        end

        def port
          raise NotImplementedError.new
        end

        def socket_path
          raise NotImplementedError.new
        end

        def address()
          raise NotImplementedError.new
        end

        def anchored
          raise NotImplementedError.new
        end

        def secure
          raise NotImplementedError.new
        end

        def timeout_sec
          raise NotImplementedError.new
        end

        def additional_headers
          raise NotImplementedError.new
        end

        def cities
          raise NotImplementedError.new
        end

        def find_city(name)
          raise NotImplementedError.new
        end

        def on_connected(agent_id, rd)
          raise NotImplementedError.new
        end

        def return_protocol_handler(agt, proto_hnd)
          raise NotImplementedError.new
        end

        def return_ship(sip)
          raise NotImplementedError.new
        end
      end
    end
  end
end
