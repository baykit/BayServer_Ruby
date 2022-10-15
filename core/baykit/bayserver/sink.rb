#
#  Ship sinks!!
#   Exception thrown by some bugs
#

module Baykit
  module BayServer
    class Sink < StandardError

      def initialize(fmt = nil, *args)
        super(if fmt == nil
                ""
              elsif args == nil
                sprintf("%s", fmt)
              else
                sprintf(fmt, *args)
              end + "(>_<)")
      end
    end
  end
end

