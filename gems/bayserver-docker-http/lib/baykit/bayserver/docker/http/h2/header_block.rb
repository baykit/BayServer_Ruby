module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class HeaderBlock

            INDEX = 1
            OVERLOAD_KNOWN_HEADER = 2
            NEW_HEADER = 3
            KNOWN_HEADER = 4
            UNKNOWN_HEADER = 5
            UPDATE_DYNAMIC_TABLE_SIZE = 6

            attr_accessor :op
            attr_accessor :index
            attr_accessor :name
            attr_accessor :value
            attr_accessor :size


            def to_s
              "#{op} index=#{index} name=#{name} value=#{value}"
            end

          end
        end
      end
    end
  end
end

