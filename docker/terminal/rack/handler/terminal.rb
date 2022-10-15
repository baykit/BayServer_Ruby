require 'rack/handler'


module Rack
  module Handler
    module Terminal

      def self.run(app, **options)
        dkr = options[:docker]
        dkr.app = app
      end
    end

    register :terminal, Terminal
  end
end

