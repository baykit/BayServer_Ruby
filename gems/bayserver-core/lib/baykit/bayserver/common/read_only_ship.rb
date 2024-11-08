require 'baykit/bayserver/ships/ship'
require 'baykit/bayserver/sink'


module Baykit
  module BayServer
    module Common

      class ReadOnlyShip < Baykit::BayServer::Ships::Ship

        include Baykit::BayServer

        #########################################
        # Implements Reusable
        #########################################
        def reset
          super
        end


        #########################################
        # Implements Ship
        #########################################

        def notify_handshake_done(proto)
          raise Sink.new
        end

        def notify_connect
          raise Sink.new
        end

        def notify_protocol_error(e)
          raise Sink.new
        end


      end
    end
  end
end

