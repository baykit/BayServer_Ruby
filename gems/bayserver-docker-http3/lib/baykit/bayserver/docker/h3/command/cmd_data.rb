module Baykit
  module BayServer
    module Docker
      module H3
        module Command
          class CmdData
            TYPE = :data

            attr_reader :stm_id

            def initialize(stm_id)
              @stm_id = stm_id
            end
          end
        end
      end
    end
  end
end
