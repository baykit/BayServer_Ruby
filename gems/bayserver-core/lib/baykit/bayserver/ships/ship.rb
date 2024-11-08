require 'baykit/bayserver/util/reusable'
require 'baykit/bayserver/util/counter'

module Baykit
  module BayServer
    module Ships
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
        attr :agent_id
        attr :rudder
        attr :transporter
        attr :initialized
        attr_accessor :keeping

        def initialize()
          @object_id = Ship.oid_counter.next
          @ship_id = INVALID_SHIP_ID
        end

        def init(agt_id, rd, tp)
          if @initialized
            raise Sink.new("Ship already initialized")
          end
          @ship_id = Ship.ship_id_counter.next
          @agent_id = agt_id
          @rudder = rd
          @transporter = tp
          @initialized = true
          BayLog.debug("%s initialized", self)
        end

        #########################################
        # implements Reusable
        #########################################
        def reset()
          BayLog.debug("%s reset", self)

          @initialized = false
          @transporter = nil
          @rudder = nil
          @agent_id = -1
          @ship_id = INVALID_SHIP_ID
          @keeping = false
        end


        #########################################
        # Other methods
        #########################################

        def id()
          @ship_id
        end

        def check_ship_id(check_id)
          if !@initialized
            raise Sink.new("#{self} ship not initialized (might be returned ship): #{check_id}")
          end
          if check_id != SHIP_ID_NOCHECK && check_id != @ship_id
            raise Sink.new("#{self} Invalid ship id (might be returned ship): #{check_id}")
          end
        end

        def resume_read(check_id)
          check_ship_id(check_id);
          @transporter.req_read(@rudder)
        end

        def post_close
          @transporter.req_close(@rudder)
        end

        #########################################
        # Abstract methods
        #########################################
        def notify_handshake_done(proto)
          raise NotImplementedError.new
        end

        def notify_connect()
          raise NotImplementedError.new
        end

        def notify_read(buf)
          raise NotImplementedError.new
        end

        def notify_eof()
          raise NotImplementedError.new
        end

        def notify_error(e)
          raise NotImplementedError.new
        end

        def notify_protocol_error(e)
          raise NotImplementedError.new
        end

        def notify_close
          raise NotImplementedError.new
        end

        def check_timeout(duration_sec)
          raise NotImplementedError.new
        end
      end
    end
  end
end

