module Baykit
  module BayServer
    module Docker
      module H3
        module Command
          class CmdFinished
            TYPE = :finished

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
