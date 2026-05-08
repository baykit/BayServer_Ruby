module Baykit
  module BayServer
    module Docker
      module Http
        # Per-agent pool of active WarpShips that support H2-style stream
        # multiplexing. Unlike WarpShipStore (which manages physical WarpShip
        # objects and is unaware of tours), this pool reasons about how many
        # tours each ship is currently carrying so that an arriving tour can
        # be routed to the least-loaded ship with capacity.
        #
        # Lifecycle: HtpWarpDocker adds a ship on on_ship_rented and removes it
        # on on_end_ship. Tour attach/detach is handled on the ship itself via
        # its tour_map; this pool only routes.
        class WarpShipPool

          def initialize
            @ships = []
            @lock = Mutex.new
          end

          # Find the WarpShip currently carrying the fewest tours that still has
          # room for one more. Returns nil when no eligible ship exists, in
          # which case the caller falls back to opening a fresh connection.
          def find_idlest
            @lock.synchronize do
              best = nil
              best_count = Float::INFINITY
              @ships.each do |ws|
                next if ws.protocol_handler.nil?
                cap = ws.warp_handler.max_multiplexed_tours
                n = ws.tour_count
                if n < cap && n < best_count
                  best = ws
                  best_count = n
                  break if n == 0  # can't be more idle
                end
              end
              best
            end
          end

          def add(ws)
            @lock.synchronize { @ships << ws }
          end

          def remove(ws)
            @lock.synchronize { @ships.delete(ws) }
          end

          def size
            @lock.synchronize { @ships.size }
          end
        end
      end
    end
  end
end
