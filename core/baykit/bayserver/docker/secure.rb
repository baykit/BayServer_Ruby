require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Secure
        include Docker   # implements

        #
        # interface
        #
        #     void setAppProtocols(String[] protocols);
        #
        #     void reloadCert() throws Exception;
        #
        #     public Transporter createTransporter();
        #
      end
    end
  end
end

