# Rack 2.x handler (Rack::Handler)
begin
  require "rack/handler"
rescue LoadError
  # Rack 3.x: Rack::Handler is not available. Provide a no-op here and rely on rackup handler.
  return
end



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

