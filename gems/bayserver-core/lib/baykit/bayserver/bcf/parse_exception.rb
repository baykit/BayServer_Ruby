require 'baykit/bayserver/config_exception'
require 'baykit/bayserver/bcf/package'

module Baykit
  module BayServer
    module Bcf
      class ParseException < ConfigException

        def initialize(file_name, line_no, msg)
          super
        end
      end
    end
  end
end