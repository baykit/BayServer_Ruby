require 'baykit/bayserver/util/reusable'
require 'baykit/bayserver/util/counter'

module Baykit
  module BayServer
    module WaterCraft
      class Ship
        include Baykit::BayServer::Util::Reusable   # implements

        include Baykit::BayServer::Util

        # class variables
        class << self
          attr :oid_counter
          attr :ship_id_counter
        end
        @oid_counter = Counter.new
        @ship_id_counter = Counter.new


        SHIP_ID_NOCHECK = -1
        INVALID_SHIP_ID = 0

        attr :object_id
        attr :ship_id
        attr :agent
        attr :postman
        attr :socket
        attr :initialized
        attr_accessor :protocol_handler
        attr_accessor :keeping

        def initialize()
          @object_id = Ship.oid_counter.next
          @ship_id = INVALID_SHIP_ID
        end

        ######################################################
        # implements Reusable
        ######################################################
        def reset()
          BayLog.debug("%s reset", self)

          @initialized = false
          @postman.reset()
          @postman = nil    # for reloading certification
          @agent = nil
          @ship_id = INVALID_SHIP_ID
          @socket = nil
          @protocol_handler = nil
          @keeping = false
        end


        ######################################################
        # Other methods
        ######################################################

        def init(skt, agt, postman)
          if @initialized
            raise Sink.new("Ship already initialized")
          end
          @ship_id = Ship.ship_id_counter.next
          @agent = agt
          @postman = postman
          @socket = skt
          @initialized = true
          BayLog.debug("%s initialized", self)
        end

        def set_protocol_handler(proto_hnd)
          @protocol_handler = proto_hnd
          proto_hnd.ship = self
          #BayLog.debug("%s protocol handler is set", self)
        end

        def id()
          @ship_id
        end

        def protocol()
          return @protocol_handler == nil ? "unknown" : @protocol_handler.protocol
        end



        def resume(check_id)
          check_ship_id(check_id);
          @postman.open_valve();
        end

        def check_ship_id(check_id)
          if !@initialized
            raise Sink.new("#{self} ship not initialized (might be returned ship): #{check_id}")
          end
          if check_id != SHIP_ID_NOCHECK && check_id != @ship_id
            raise Sink.new("#{self} Invalid ship id (might be returned ship): #{check_id}")
          end
        end
      end
    end
  end
end

