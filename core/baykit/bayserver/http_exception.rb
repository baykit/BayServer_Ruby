require 'baykit/bayserver/bay_exception'
require 'baykit/bayserver/util/http_status'

module Baykit
  module BayServer

    class HttpException < BayException
      include Baykit::BayServer::Util

      attr :status    # Http status
      attr_accessor :location  # for 302

      def initialize(status, fmt=nil, *args)
        super(fmt, *args)
        @status = status
        if @status < 300 || @status >= 600
          raise RuntimeError.new "IllegalArgument"
        end
      end

      def message
        "HTTP #{@status} #{super}"
      end

      def self.moved_temp(location)
        e = HttpException.new(HttpStatus::MOVED_TEMPORARILY, location)
        e.location = location
        return e
      end

    end
  end
end
