require 'baykit/bayserver/tours/tour_handler'

module Baykit
  module BayServer
    module Common
        module InboundHandler  # interface
          include Baykit::BayServer::Tours::TourHandler # extends
        end
    end
  end
end

