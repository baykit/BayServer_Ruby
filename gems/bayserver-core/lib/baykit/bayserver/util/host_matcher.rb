module Baykit
  module BayServer
    module Util
      class HostMatcher
        MATCH_TYPE_ALL = 1
        MATCH_TYPE_EXACT = 2
        MATCH_TYPE_DOMAIN = 3

        attr :match_type
        attr :host
        attr :domain

        def initialize(host)
          if host == "*"
            @match_type = MATCH_TYPE_ALL
          elsif host.start_with?("*.")
            @match_type = MATCH_TYPE_DOMAIN
            @domain = host[2, -1]
          else
            @match_type = MATCH_TYPE_EXACT
            @host = host
          end
        end


        def match(remote_host)
          if @match_type == MATCH_TYPE_ALL
            # all match
            return true
          end

          if remote_host == nil
            return false
          end

          if @match_type == MATCH_TYPE_EXACT
            # exact match
            remote_host == @host
          else
            # domain match
            remote_host.end_with?(@domain)
          end
        end
      end
    end
  end
end

