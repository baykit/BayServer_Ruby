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

        end
    end
  end
end
