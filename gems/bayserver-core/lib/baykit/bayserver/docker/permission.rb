require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Permission
        include Docker # implements

        def socket_admitterd(rd)
          raise NotImplementedError.new
        end

        def tour_admitted(tour)
          raise NotImplementedError.new
        end
      end
    end
  end
end
