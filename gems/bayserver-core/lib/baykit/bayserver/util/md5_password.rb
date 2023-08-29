require 'digest/md5'

module Baykit
  module BayServer
    module Util
      class MD5Password
        def MD5Password.encode(password)
          digest = Digest::MD5.new
          digest.update(password)
          return digest.digest.unpack("H*")[0]
        end

        def bytesToString(bytes)
          ret = ""
          bytes.each do |b|
            b.to_s(16)
            ret.concat(b)
          end
          return ret
        end
      end
    end
  end
end