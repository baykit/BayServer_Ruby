require 'baykit/bayserver/util/message'
require 'baykit/bayserver/util/locale'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2ErrorCode < Baykit::BayServer::Util::Message
            include Baykit::BayServer::Util

            NO_ERROR = 0x0
            PROTOCOL_ERROR = 0x1
            INTERNAL_ERROR = 0x2
            FLOW_CONTROL_ERROR = 0x3
            SETTINGS_TIMEOUT = 0x4
            STREAM_CLOSED = 0x5
            FRAME_SIZE_ERROR = 0x6
            REFUSED_STREAM = 0x7
            CANCEL = 0x8
            COMPRESSION_ERROR = 0x9
            CONNECT_ERROR = 0xa
            ENHANCE_YOUR_CALM = 0xb
            INADEQUATE_SECURITY = 0xc
            HTTP_1_1_REQUIRED = 0xd

            class << self
              attr :desc
              attr :msg
            end

            def self.initialized
              @desc = {}
              @msg = nil
            end

            def self.init
              if(@msg != nil)
                return
              end

              prefix = BayServer.bserv_lib + "/conf/h2_messages"
              @msg = H2ErrorCode.new()
              @msg.init(prefix, Locale.new('ja', 'JP'))
            end

          end
        end
      end
    end
  end
end

