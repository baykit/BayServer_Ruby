module Baykit
  module BayServer
    module Util
      class Cities

        attr :any_city
        attr :cities

        def initialize
          @any_city = nil
          @cities = []
        end

        def add(c)
          if c.name == "*"
            @any_city = c
          else
            @cities << c
          end
        end


        def find_city(name)
          # Check exact match
          @cities.each do |city|
            if city.name == name
              return city
            end
          end
          return @any_city
        end

        def cities()
          ret = @cities.dup
          if @any_city != nil
            ret << @any_city
          end
          return ret
        end

      end
    end
  end
end

