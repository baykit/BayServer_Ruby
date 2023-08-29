module Baykit
  module BayServer
    module Util
      class IpMatcher
        attr :match_all
        attr :net_addr
        attr :mask_addr

        def initialize(ip_desc)
          @match_all = (ip_desc == "*")

          if !@match_all
            parse_ip(ip_desc)
          end
        end

        def match(ip)
          BayLog.debug("match_ip %s net=%s mask=%s", ip, @net_addr, @mask_addr)
          if @match_all
            return true
          else
            if ip.ipv4? != @mask_addr.ipv4?
              # IPv4 and IPv6 don't match each other
              return false
            end

            if ip & @mask_addr != @net_addr
              return false
            end

            return true
          end
        end

        def get_ip_addr(ip)
          return IPAddr.new(ip)
        end

        private
        def parse_ip(ip_desc)
          items = ip_desc.split("/")
          if items.length == 0
            raise RuntimeError.new(BayMessage.get(:CFG_INVALID_IP_DESC, ip_desc))
          end

          ip = items[0]
          if items.length == 1
            mask = "255.255.255.255"
          else
            mask = items[1]
          end

          ip_addr = get_ip_addr(ip)
          @mask_addr = get_ip_addr(mask)

          if ip_addr.ipv4? != @mask_addr.ipv4?
            raise RuntimeError.new(BayMessage.get(:CFG_IPV4_AND_IPV6_ARE_MIXED, ip_desc))
          end

          @net_addr = ip_addr & @mask_addr
        end


      end
    end
  end
end