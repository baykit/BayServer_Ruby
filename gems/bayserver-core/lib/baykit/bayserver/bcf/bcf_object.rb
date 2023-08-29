module Baykit
  module BayServer
    module Bcf
      class BcfObject
        attr :file_name
        attr :line_no

        def initialize(file_name, line_no)
          @file_name = file_name
          @line_no = line_no
        end
      end
    end
  end
end
