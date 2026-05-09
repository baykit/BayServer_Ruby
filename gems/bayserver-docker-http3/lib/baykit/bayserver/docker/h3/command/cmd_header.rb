module Baykit
  module BayServer
    module Docker
      module H3
        module Command
          class CmdHeader
            TYPE = :headers

            attr_reader :stm_id, :req_headers

            def initialize(stm_id, req_headers)
              @stm_id = stm_id
              @req_headers = req_headers
            end
          end
        end
      end
    end
  end
end
