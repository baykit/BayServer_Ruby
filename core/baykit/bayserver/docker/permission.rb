require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Permission
        include Docker # implements

        #
        # interface
        #
        #     void checkAdmitted(SocketChannel ch) throws HttpException;
        #     void checkAdmitted(Tour tour) throws HttpException;
        # 
      end
    end
  end
end
