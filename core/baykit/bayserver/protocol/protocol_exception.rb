module Baykit
  module BayServer
    module Protocol
      class ProtocolException < StandardError
        def initialize(fmt = nil, *args)
          super(if fmt == nil
                  nil
                elsif args == nil
                  sprintf("%s", fmt)
                else
                  sprintf(fmt, *args)
                end)
          super
        end
      end
    end
  end
end
