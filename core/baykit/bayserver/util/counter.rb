module Baykit
  module BayServer
    module Util
      class Counter
        attr :counter
        attr :mutex

        def initialize(init=1)
          @counter = init
          @mutex = Mutex.new
        end

        def next
          @mutex.synchronize do
            c = @counter
            @counter += 1
            c
          end
        end
      end
    end
  end
end