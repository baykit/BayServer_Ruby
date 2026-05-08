require 'baykit/bayserver/protocol/protocol_exception'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          # A ProtocolException that carries the specific HTTP/2 error code
          # that should appear in the resulting GOAWAY frame. The base class always
          # maps to PROTOCOL_ERROR; this subclass lets call sites pick
          # FLOW_CONTROL_ERROR, COMPRESSION_ERROR, etc.
          class H2ProtocolException < Baykit::BayServer::Protocol::ProtocolException
            attr :error_code

            def initialize(error_code, message)
              super(message)
              @error_code = error_code
            end
          end
        end
      end
    end
  end
end
