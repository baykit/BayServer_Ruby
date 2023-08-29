require 'baykit/bayserver/util/counter'
module Baykit
  module BayServer
      module Train
        class Train
          include Baykit::BayServer::Util

          #
          # abstract methods
          #
          # depart()

          # define class instance accessor
          class << self
            attr :train_id_counter
          end
          @train_id_counter = Counter.new()

          attr :tour
          attr :tour_id
          attr :train_id


          def initialize(tur)
            @tour = tur
            @tour_id = tur.id()
            @train_id = Train.train_id_counter.next()
          end

          def to_s
            "train##{@train_id}"
          end

          def run
            BayLog.debug("%s Start train (%s)", self, @tour)

            begin
              depart()
            rescue HttpException => e
              @tour.res.send_http_exception @tour_id, e
            rescue => e
              BayLog.error_e e
              @tour.res.end_content(@tour_id)
            end

            BayLog.debug("%s End train", self)
          end


        end
      end
  end
end

