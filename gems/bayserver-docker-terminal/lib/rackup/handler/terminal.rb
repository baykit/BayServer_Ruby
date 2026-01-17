require "rackup"


module Rackup
  module Handler
    module Terminal

      def self.run(app, **options)
        dkr = options[:docker]
        dkr.app = app
      end
    end
  end
end

Rackup::Handler.register :terminal, Rackup::Handler::Terminal
