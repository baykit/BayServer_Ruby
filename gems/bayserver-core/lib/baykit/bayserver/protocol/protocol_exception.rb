#
# ProtocolException is thrown when protocol-level violations are detected,
# such as invalid packet framing or incorrect packet ordering.
# (Invalid HTTP headers or content length values result in an HttpException,
# which causes a 400 Bad Request response to be returned to the client.)
#
module Baykit
  module BayServer
    module Protocol
      class ProtocolException < StandardError
        def initialize(fmt = nil, *args)
          super(if fmt == nil
                  nil
                elsif args.empty?
                  sprintf("%s", fmt)
                else
                  sprintf(fmt, *args)
                end)
        end
      end
    end
  end
end
