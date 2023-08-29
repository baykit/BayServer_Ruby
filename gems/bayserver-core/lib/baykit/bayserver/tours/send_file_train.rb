require 'baykit/bayserver/train/train'

require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/http_status'


module Baykit
  module BayServer
    module Tours
      class SendFileTrain < Baykit::BayServer::Train::Train

        include Baykit::BayServer::Util

        attr :file

        def initialize(tur, file)
          super(tur)
          @file = file
        end

        ######################################################
        # implements Train
        ######################################################

        def run()

          @tour.res.set_consume_listener do |len, resume| end

          size = @tour.ship.protocol_handler.max_packet_data_size
          buf = StringUtil.alloc(size)
          File.open(file, "r") do |fd|
            begin
              while true

                while !@tour.res.available
                  sleep(0.1)
                end

                begin
                  fd.sysread(size, buf);
                rescue EOFError => e
                  break
                rescue Exception => e
                  @tour.res.send_error(@tour_id, HttpStatus::INTERNAL_SERVER_ERROR, e)
                  break
                end

                @tour.res.send_content(@tour_id, buf, 0, buf.length);

                while !@tour.res.available
                  sleep(0.1)
                end
              end

              @tour.res.end_content(@tour_id)
            rescue Exception => e
              BayLog.error_e(e);
            end
          end
        end
      end
    end
  end
end
