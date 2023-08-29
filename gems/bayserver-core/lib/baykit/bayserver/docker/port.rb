require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Port
        include Docker  # implements

        def address()
          raise NotImplementedError()
        end

        def check_admitted(skt)
          raise NotImplementedError()
        end

        def find_city(name)
          raise NotImplementedError()
        end

        def new_transporter(agt, skt)
          raise NotImplementedError()
        end

        def check_admitted(skt)
          raise NotImplementedError()
        end

        def return_protocol_handler(agt, proto_hnd)
          raise NotImplementedError()
        end

        def return_ship(sip)
          raise NotImplementedError()
        end
      end
    end
  end
end
