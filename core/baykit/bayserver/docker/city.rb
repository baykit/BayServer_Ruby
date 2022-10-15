require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module City
        include Baykit::BayServer::Docker::Docker

        #
        # interface
        #
        #     String name();
        #     List<Club> clubs();
        #     List<Town> towns();
        #     void enter(Tour tour) throws HttpException;
        #     Trouble getTrouble();
        #     void log(Tour tour);
        #
      end
    end
  end
end
