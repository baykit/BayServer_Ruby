module Baykit
  module BayServer
    module Util
      class ClassUtil
        def self.get_local_name(cls)
          name = cls.name
          p = name.rindex(':')
          if(p != nil)
            name = name[p + 1 .. -1]
          end
          return name
        end
      end
    end
  end
end

