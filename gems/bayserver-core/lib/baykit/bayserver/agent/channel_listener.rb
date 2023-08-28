
module Baykit
  module BayServer
    module Agent
      module ChannelListener # interface

        def on_readable(chk_ch)
          raise NotImplementedError()
        end

        def on_writable(chk_ch)
          raise NotImplementedError()
        end

        def on_connectable(chk_ch)
          raise NotImplementedError()
        end

        def on_error(chk_ch, e)
          raise NotImplementedError()
        end

        def on_closed(chk_ch)
          raise NotImplementedError()
        end

        def check_timeout(chk_ch, duration)
          raise NotImplementedError()
        end

      end
    end
  end
end

