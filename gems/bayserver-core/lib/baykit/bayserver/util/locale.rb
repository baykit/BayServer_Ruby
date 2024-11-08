module Baykit
  module BayServer
    module Util
      class Locale
        attr :language
        attr :country

        def initialize(language, country)
          @language = language
          @country = country
        end


        def self.default()
          lang = ENV['LANG']
          if StringUtil.set?(lang)
            begin
              language = lang[0, 2]
              country = lang[3, 2]
              return Locale.new(language, country)
            rescue => e
              BayLog.error_e(e)
            end
          end
          return Locale.new("en", "US")
        end
      end
    end
  end
end