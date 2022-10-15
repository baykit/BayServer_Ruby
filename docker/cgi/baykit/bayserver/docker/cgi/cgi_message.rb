require 'baykit/bayserver/bayserver'
require 'baykit/bayserver/util/message'
require 'baykit/bayserver/util/locale'

module Baykit
  module BayServer
    module Docker
      module Cgi
        class CgiMessage
          include Util

          class << self
            def initialize()
              self.init()
            end
          end

          @@msg = Message.new

          def self.init()
            @msg.init(BayServer.bserv_home + "/lib/conf/cgi_messages", Locale.default())
          end

          def self.get(key, *args)
            return @@msg.get(key, *args)
          end
        end

      end

    end
  end
end