
module Baykit
  module BayServer
    module Agent
      module ChannelListener # interface

        def on_readable(chk_ch)
          raise NotImplementedError.new
        end

        def on_writable(chk_ch)
          raise NotImplementedError.new
        end

        def on_connectable(chk_ch)
          raise NotImplementedError.new
        end

        def on_error(chk_ch, e)
          raise NotImplementedError.new
        end

        def on_closed(chk_ch)
          raise NotImplementedError.new
        end

        def check_timeout(chk_ch, duration)
          raise NotImplementedError.new
        end

      end
    end
  end
end

