require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Agent
      module Multiplexer
        class WriteUnit

          attr :buf
          attr :adr
          attr :tag
          attr :listener

          def initialize(buf, adr, tag, lis)
            @buf = buf
            @adr = adr
            @tag = tag
            @listener = lis
          end

          def done()
            if @listener != nil
              @listener.call()
            end
          end
        end
      end
    end
  end
end