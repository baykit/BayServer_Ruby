require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/http_exception'

require 'baykit/bayserver/watercraft/ship'
require 'baykit/bayserver/util/counter'


module Baykit
  module BayServer
    module Tours
      class Tour
        include Baykit::BayServer
        include Baykit::BayServer::WaterCraft
        include Baykit::BayServer::Util
        include Baykit::BayServer::Util::Reusable # implements

        class TourState
          UNINITIALIZED = 0
          PREPARING = 1
          RUNNING = 2
          ABORTED = 3
          ENDED = 4
          ZOMBIE = 5
        end

        # class variables
        class << self
          attr :oid_counter
          attr :tour_id_counter
        end
        @oid_counter = Counter.new
        @tour_id_counter = Counter.new

        TOUR_ID_NOCHECK = -1
        INVALID_TOUR_ID = 0

        attr :ship
        attr :ship_id
        attr :obj_id #object id

        attr :tour_id
        attr :error_handling
        attr_accessor :town
        attr_accessor :city
        attr_accessor :club

        attr :req
        attr :res

        attr :lock

        attr_accessor :interval
        attr_accessor :is_secure
        attr_accessor :state

        attr_accessor :error


        def initialize()
          @obj_id = Tour.oid_counter.next
          @req = TourReq.new(self)
          @res = TourRes.new(self)
          @lock = Mutex.new
          reset()
        end

        def to_s()
          return "#{@ship} tours##{@tour_id}/#{@obj_id}[key=#{@req.key}]"
        end

        ######################################################
        # implements Reusable
        ######################################################
        def reset()
          @city = nil
          @town = nil
          @club = nil
          @error_handling = false

          @tour_id = INVALID_TOUR_ID
          @interval = 0
          @is_secure = false
          change_state(TOUR_ID_NOCHECK, TourState::UNINITIALIZED)
          @error = nil

          @req.reset()
          @res.reset()
        end

        def id()
          @tour_id
        end

        def init(key, sip)
          if initialized?
            raise Sink.new("#{@ship} Tour already initialized: #{self}")
          end

          @ship = sip
          @ship_id = sip.ship_id
          if @ship_id == Ship::INVALID_SHIP_ID
            raise Sink.new()
          end
          @tour_id = Tour.tour_id_counter.next
          change_state(TOUR_ID_NOCHECK, TourState::PREPARING)

          @req.init(key)
          @res.init()
          BayLog.debug("%s initialized", self)
        end

        def go
          change_state(TOUR_ID_NOCHECK, TourState::RUNNING)

          city = @ship.port_docker.find_city(@req.req_host)
          if city == nil
            city = BayServer.find_city(@req.req_host)
          end
          BayLog.debug("%s GO TOUR! ...( ^_^)/: city=%s url=%s", self, @req.req_host, @req.uri);

          if city == nil
            raise HttpException.new HttpStatus::NOT_FOUND, @req.uri
          else
            begin
              city.enter(self)
            rescue Sink => e
              raise e
            rescue HttpException => e
              BayLog.error_e(e)
              raise e
            rescue => e
              BayLog.error_e(e)
              raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR, e.message)
            end
          end
        end

        def valid?()
          return @state == TourState::PREPARING || @state == TourState::RUNNING
        end

        def running?()
          return @state == TourState::RUNNING
        end

        def zombie?()
          return @state == TourState::ZOMBIE
        end

        def aborted?()
          return @state == TourState::ABORTED
        end

        def initialized?()
          return state != TourState::UNINITIALIZED
        end

        def change_state(chk_id, new_state)
          BayLog.debug("%s change state: %s", self, new_state)
          check_tour_id(chk_id)
          @state = new_state
        end



        def secure?
          @is_secure
        end

        def inspect
          return to_s
        end

        def check_tour_id(chk_id)
          if chk_id == TOUR_ID_NOCHECK
            return
          end

          if !initialized?
            raise Sink.new("%s Tour not initialized", self)
          end
          if chk_id != @tour_id
            raise Sink.new("%s Invalid tours id: %s", self, chk_id== nil ? "" : chk_id)
          end
        end


      end
    end
  end
end
