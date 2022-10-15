require 'baykit/bayserver/util/message'

module Baykit
  module BayServer

    class BayMessage
      include Util

      @@msg = Message.new

      def self.init(conf_name, locale)
        @@msg.init(conf_name, locale)
      end

      def self.get(key, *args)
        @@msg.get(key, *args)
      end
    end
  end
end