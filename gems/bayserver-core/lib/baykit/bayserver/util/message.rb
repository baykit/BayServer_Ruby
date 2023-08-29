require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/bay_log'

module Baykit
  module BayServer

    module Util
      class Message
        include Bcf

        attr_reader :messages

        def initialize
          @messages = {}
        end

        def init(file_prefix, locale)
          lang = locale.language
          file = file_prefix + ".bcf"
          if(StringUtil.set?(lang) && lang != "en")
            file = file_prefix + "_" + lang + ".bcf"
          end

          if(!File.exist?(file))
            BayLog.warn("Cannot find message send_file: %s", file)
            return
          end

          p = BcfParser.new()
          doc = p.parse(file)

          doc.content_list.each do |o|
            if(o.instance_of? BcfKeyVal)
              messages[o.key.to_sym] = o.value
            end
          end
        end

        #
        # key : symbol
        #
        def get(key, *args)
          if !key.instance_of? Symbol
            raise RuntimeError "Key must be symbol"
          end
          msg = messages[key]
          if msg == nil
            msg = key.to_s
          end
          sprintf(msg, *args)
        end
      end
    end
  end
end