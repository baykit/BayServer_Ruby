require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/http_exception'

require 'baykit/bayserver/ships/ship'
require 'baykit/bayserver/util/counter'


module Baykit
  module BayServer
    module Tours
      module TourHandler

        # Send HTTP headers to client
        def send_res_headers(tur)
          raise NotImplementedError.new
        end

        # Send Contents to client
        def send_res_content(tur, bytes, ofs, len, &lis)
          raise NotImplementedError.new
        end

        # Send end of contents to client.
        def send_end_tour(tur, &lis)
          raise NotImplementedError.new
        end

        # Send protocol error to client
        def on_protocol_error(e)
          raise NotImplementedError.new
        end

      end
    end
  end
end
