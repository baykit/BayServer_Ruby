require 'baykit/bayserver/tours/tour_handler'

module Baykit
  module BayServer
    module Common
        module WarpHandler # interface
          include Baykit::BayServer::Tours::TourHandler

          def next_warp_id()
            raise NotImplementedError.new
          end

          def new_warp_data(warp_id)
            raise NotImplementedError.new
          end

          #
          # Verify if protocol is allowed
          #
          def verify_protocol(protocol)
            raise NotImplementedError.new
          end

          # Maximum concurrent tours that can ride on a single WarpShip.
          # Default 1 = exclusive (H1, FCGI, AJP). H2 overrides to 100.
          def max_multiplexed_tours
            1
          end

        end
    end
  end
end
