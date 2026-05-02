require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module City # interface
        include Baykit::BayServer::Docker::Docker # implements

        def name
          raise NotImplementedError.new
        end

        def clubs
          raise NotImplementedError.new
        end

        def towns
          raise NotImplementedError.new
        end

        def enter(tur)
          raise NotImplementedError.new
        end

        def get_trouble
          raise NotImplementedError.new
        end

        def log(tur)
          raise NotImplementedError.new
        end

      end
    end
  end
end
