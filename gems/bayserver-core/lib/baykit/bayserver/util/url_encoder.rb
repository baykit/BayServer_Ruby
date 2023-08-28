module Baykit
  module BayServer
    module Util
      class URLEncoder
        def URLEncoder.encode_tilde(url)
          buf = ""
          url.each_char do |c|
            if(c == "~")
              buf.concat("%7E")
            else
              buf.concat(c)
            end
          end
          return buf
        end
      end
    end
  end
end
