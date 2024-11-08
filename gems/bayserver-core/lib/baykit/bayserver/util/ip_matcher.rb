module Baykit
  module BayServer
    module Util
      class IpMatcher
        attr :match_all
        attr :cidr_ip

        def initialize(ip_desc)
          @match_all = (ip_desc == "*")

          if !@match_all
            parse_cidr(ip_desc)
          end
        end

        def match(ip)
          BayLog.debug("match_ip %s net=%s mask=%s", ip, @net_addr, @mask_addr)
          if @match_all
            return true
          else
            return @cidr_ip.include?(ip)
          end
        end

        private
        def parse_cidr(cidr)
          begin
            @cidr_ip = IPAddr.new(cidr)
          rescue => e
            BayLog.error_e(e)
            raise RuntimeError.new(BayMessage.get(:CFG_INVALID_IP_DESC, cidr))
          end
        end
      end
    end
  end
end