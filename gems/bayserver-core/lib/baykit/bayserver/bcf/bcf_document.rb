require 'baykit/bayserver/bcf/package'

module Baykit
  module BayServer
    module Bcf

      class BcfDocument
        attr :content_list

        def initialize
          @content_list = []
        end

        def print_document
          print_content_list(@content_list, 0)
        end

        def print_content_list(list, indent)
          list.each do |o|
            print_indent(indent)
            if o.instance_of?(BcfElement)
              puts "Element(#{o.name}, #{o.arg}){"
              print_content_list(o.content_list, indent + 1)
              print_indent(indent)
              p
            else
              puts "KeyVal(#{o.key}, #{o.value})"
              p
            end
          end
        end
        private :print_content_list

        def print_indent(indent)
          indent.times do
            print " "
          end
        end
        private :print_indent

      end
    end
  end
end
