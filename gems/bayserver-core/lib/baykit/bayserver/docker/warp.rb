require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Warp # interface
        include Docker # implements

        def host
          raise NotImplementedError.new
        end

        def port
          raise NotImplementedError.new
        end
        def warp_base
          raise NotImplementedError.new
        end

        def timeout_sec
          raise NotImplementedError.new
        end

        def keep(warp_ship)
          raise NotImplementedError.new
        end

        def on_end_ship(warp_ship)
          raise NotImplementedError.new
        end
      end
    end
  end
end
