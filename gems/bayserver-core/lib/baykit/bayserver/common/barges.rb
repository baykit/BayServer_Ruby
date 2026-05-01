module Baykit
  module BayServer
    module Common
      class Barges

        # Default barge docker
        attr :any_barge

        # Barge dockers
        attr :barges

        def initialize
          @any_barge = nil
          @barges = []
        end

        def add(b)
          if b.name == "*"
            @any_barge = b
          else
            @barges << b
          end
        end


        def find_barge(path)
          # Check exact match
          @barges.each do |b|
            if match(b, path)
              return b
            end
          end
          return @any_barge
        end

        def match(b, path)
          return true
        end

      end
    end
  end
end

