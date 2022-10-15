require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Harbor
        include Docker

        FILE_SEND_METHOD_SELECT = 1
        FILE_SEND_METHOD_SPIN = 2
        FILE_SEND_METHOD_TAXI = 3

        #
        # interface
        #
        #     String charset();
        #     Locale locale();
        #     int shipAgents();
        #     int trainRunners();
        #     int maxShips();
        #     Trouble getTrouble();
        #     int socketTimeoutSec();
        #     int keepTimeoutSec();
        #     boolean traceHeader();
        #     int tourBufferSize();
        #     String redirectFile();
        #     int bayPort();
        #     boolean gzipComp();
        #     AsyncFileMethod asyncFileMethod();
        #
      end
    end
  end
end
