require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Common
        class WriteUnit
          include Baykit::BayServer::Util::Reusable # implements (for ObjectStore)

          attr :buf
          attr :adr
          attr :tag
          attr :listener

          # ObjectStore factory uses a no-arg lambda; .new takes no args.
          # Field assignment happens via init() after rent.
          def initialize(buf=nil, adr=nil, tag=nil, &lis)
            @buf = buf
            @adr = adr
            @tag = tag
            @listener = lis
          end

          # Set fields after rent from the per-RudderState pool.
          def init(buf, adr, tag, &lis)
            @buf = buf
            @adr = adr
            @tag = tag
            @listener = lis
          end

          # Release strong references before returning to the pool so
          # the previous Packet (@tag), callback Proc (@listener), and
          # bytes can be GC'd while the WriteUnit shell stays cached.
          def reset
            @buf = nil
            @adr = nil
            @tag = nil
            @listener = nil
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
