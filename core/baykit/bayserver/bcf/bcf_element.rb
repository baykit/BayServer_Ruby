require 'baykit/bayserver/bcf/package'

module Baykit
  module BayServer
    module Bcf

      class BcfElement < BcfObject
        attr :name
        attr :arg
        attr :content_list

        def initialize(name, arg, file_name, line_no)
          super file_name, line_no
          @name = name
          @arg = arg
          @content_list = []
        end

        def get_value(key)
          content_list.each do |o|
            if o.instance_of?(BcfKeyVal) && o.key.casecmp?(key)
              return o.value
            end
          end
          nil
        end
      end
    end
  end
end