# frozen_string_literal: true

module Baykit
  module BayServer
    module Util
      class URLEncoder
        # Percent-encode '~' (and only '~') in a URL. The vast majority of
        # request URIs do not contain '~', so the fast path is to return
        # the input unchanged without iterating each char or allocating
        # a working buffer.
        def URLEncoder.encode_tilde(url)
          return url unless url.include?("~")
          buf = String.new(capacity: url.bytesize + 8)
          url.each_char do |c|
            if c == "~"
              buf << "%7E"
            else
              buf << c
            end
          end
          buf
        end
      end
    end
  end
end
