require 'baykit/bayserver/docker/http/h2/package'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module Huffman

            class HNode
              attr_accessor :value
              attr_accessor :one
              attr_accessor :zero

              def initialize
                @value = -1
                @one = nil
                @zero = nil
              end
            end
          end
        end
      end
    end
  end
end


