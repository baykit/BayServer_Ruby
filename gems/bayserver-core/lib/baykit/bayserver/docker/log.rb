require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Log
        include Docker # implements

        #
        # interface
        #
        #     void log(Tour tour) throws IOException;
        #
      end
    end
  end
end
