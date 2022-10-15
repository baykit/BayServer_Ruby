require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Reroute
        include Docker   # implements

        #
        # interface
        #
        # String reroute(Town twn, String uri)
        #
      end
    end
  end
end
