require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Common
        class WriteUnit

          attr :buf
          attr :adr
          attr :tag
          attr :listener

          def initialize(buf, adr, tag, &lis)
            @buf = buf
            @adr = adr
            @tag = tag
            @listener = lis
          end

          def done(buffer_available = true)
            if @listener != nil
              @listener.call(buffer_available)
            end
          end
        end
    end
  end
end