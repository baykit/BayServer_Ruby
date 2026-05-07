require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Agent
      module Letters
        class Letter
          include Baykit::BayServer::Util::Reusable # implements (for ObjectStore)

          attr_accessor :rudder
          attr_accessor :multiplexer

          def initialize
          end

          def init(rd, mpx)
            @rudder = rd
            @multiplexer = mpx
          end

          def reset
            @rudder = nil
            @multiplexer = nil
          end
        end
      end
    end
  end
end
