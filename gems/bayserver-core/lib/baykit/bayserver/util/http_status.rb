require 'baykit/bayserver/bcf/package'

module Baykit
  module BayServer
    module Util
      class HttpStatus
        include Baykit::BayServer::Bcf

        #
        # Known status
        # 
        OK = 200
        MOVED_PERMANENTLY = 301
        MOVED_TEMPORARILY = 302
        NOT_MODIFIED = 304
        BAD_REQUEST = 400
        UNAUTHORIZED = 401
        FORBIDDEN = 403
        NOT_FOUND = 404
        UPGRADE_REQUIRED = 426
        INTERNAL_SERVER_ERROR = 500
        SERVICE_UNAVAILABLE = 503
        GATEWAY_TIMEOUT = 504
        HTTP_VERSION_NOT_SUPPORTED = 505

        class << self
          attr :status
          attr :initialized
        end
        @status = {}
        @initialized = false

        def self.init(bcf_file)
          if(@initialized)
            return
          end

          p = BcfParser.new()
          doc = p.parse(bcf_file)
          doc.content_list.each do |kv|
            if(kv.instance_of?(BcfKeyVal))
              @status[kv.key.to_i] = kv.value
            end
          end
          @initialized = true
        end

        def self.description(status_code)
          desc = @status[status_code]
          if(desc == nil)
            BayLog.error("Status #{status_code} is invalid.")
            return status_code.to_s()
          else
            return desc
          end
        end
      end
    end
  end
end
