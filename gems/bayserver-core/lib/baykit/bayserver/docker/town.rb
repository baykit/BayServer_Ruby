require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Town
        include Docker # implements
        MATCH_TYPE_MATCHED = 1
        MATCH_TYPE_NOT_MATCHED = 2
        MATCH_TYPE_CLOSE = 3

        def name
          raise NotImplementedError.new
        end

        def city
          raise NotImplementedError.new
        end

        def location
          raise NotImplementedError.new
        end

        def welcome_file
          raise NotImplementedError.new
        end

        def clubs
          raise NotImplementedError.new
        end

        def reroute(uri)
          raise NotImplementedError.new
        end

        def matches(uri)
          raise NotImplementedError.new
        end

        def check_admitted(tur)
          raise NotImplementedError.new
        end
      end
    end
  end
end
