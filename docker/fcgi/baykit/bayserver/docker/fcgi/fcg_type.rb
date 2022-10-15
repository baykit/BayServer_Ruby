module Baykit
  module BayServer
    module Docker
      module Fcgi
        class FcgType

          BEGIN_REQUEST = 1
          ABORT_REQUEST = 2
          END_REQUEST = 3
          PARAMS = 4
          STDIN = 5
          STDOUT = 6
          STDERR = 7
          DATA = 8
          GET_VALUES = 9
          GET_VALUES_RESULT = 10
          UNKNOWN_TYPE = 11

        end
      end
    end
  end
end
