require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Town
        include Docker # implements
        MATCH_TYPE_MATCHED = 1
        MATCH_TYPE_NOT_MATCHED = 2
        MATCH_TYPE_CLOSE = 3

        #
        # interface
        #
        #     String name();
        #     City city();
        #     String location();
        #     String welcomeFile();
        #     ArrayList<Club> clubs();
        #     String reroute(String uri);
        #     MatchType matches(String uri);
        #     void checkAdmitted(Tour tour) throws HttpException;
        #     String reroute(String uri);
        #     MatchType matches(String uri);
        #     void checkAdmitted(Tour tour) throws HttpException;
        #
      end
    end
  end
end
