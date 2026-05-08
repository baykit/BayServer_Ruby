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

        # Mark a ship as no longer eligible for sharing new tours (remove
        # from the multiplex pool, if any). Called by H2 warp handlers on
        # GOAWAY. Default no-op for non-multiplex dockers.
        def exclude_from_pool(warp_ship)
        end
      end
    end
  end
end
