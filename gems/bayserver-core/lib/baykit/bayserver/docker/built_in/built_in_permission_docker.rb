require 'ipaddr'

require 'baykit/bayserver/http_exception'
require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/docker/permission'
require 'baykit/bayserver/common/groups'
require 'baykit/bayserver/util/headers'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/util/host_matcher'
require 'baykit/bayserver/util/ip_matcher'


module Baykit
  module BayServer
    module Docker
      module BuiltIn
        class BuiltInPermissionDocker < Baykit::BayServer::Docker::Base::DockerBase
          include Permission # import

          include Baykit::BayServer
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util
          include Baykit::BayServer::Common

          class CheckItem
            attr :matcher
            attr :admit

            def initialize(matcher, admit)
              @matcher = matcher
              @admit = admit
            end

            def socket_admitted(rd)
              matcher.match_socket(rd) == @admit
            end

            def tour_admitted(tur)
              matcher.match_tour(tur) == @admit
            end
          end

          module PermissionMatcher # interface

            def match_socket(rd)
              raise NotImplementedError.new
            end

            def match_tour(tur)
              raise NotImplementedError.new
            end
          end


          class HostPermissionMatcher
            include Baykit::BayServer::Util
            include PermissionMatcher # implements

            attr :mch

            def initialize(hostPtn)
              @mch = HostMatcher.new(hostPtn)
            end

            def match_socket(rd)
              return @mch.match(rd.io.remote_address.getnameinfo[0])
            end

            def match_tour(tur)
              return @mch.match(tur.req.remote_host())
            end
          end

          class IpPermissionMatcher
            include Baykit::BayServer::Util
            include PermissionMatcher # implements

            attr :mch

            def initialize(ip_desc)
              @mch = IpMatcher.new(ip_desc)
            end

            def match_socket(rd)
              return @mch.match(rd.io.remote_address.ip_address)
            end

            def match_tour(tur)
               begin
                return @mch.match(IPAddr.new(tur.req.remote_address))
              rescue => e
                BayLog.error_e(e)
                false
              end
            end

          end

          attr :check_list
          attr :groups

          def initialize
            @check_list = []
            @groups = []
          end

          def init(elm, parent)
            super
          end

          def init_key_val(kv)
            case kv.key.downcase
            when "admit", "allow"
              parse_value(kv).each do |permission_matcher|
                @check_list.append(CheckItem.new(permission_matcher, true))
              end

            when "refuse", "deny"
              parse_value(kv).each do |permission_matcher|
                @check_list.append(CheckItem.new(permission_matcher, false))
              end

            when "group"
              kv.value.split(" ").each do |group_name|
                g = BayServer.harbor.groups.get_group(group_name)
                if g == nil
                  raise ConfigException.new(kv.file_name, kv.line_no, BayMessage.get(:CFG_GROUP_NOT_FOUND, group_name))
                end
                @groups.append(g)
              end

            else
              raise ConfigException.new(kv.file_name, kv.line_no, BayMessage.get(:CFG_INVALID_PERMISSION_DESCRIPTION, kv.value))

            end

            return true
          end

          def socket_admitted(skt)
            # Check remote host
            isOk = true
            @check_list.each do |chk|
              if chk.admit
                if chk.socket_admitted(skt)
                  isOk = true
                  break
                end
              else
                if !chk.socket_admitted(skt)
                  isOk = false
                  break
                end
              end
            end

            if !isOk
              BayLog.error("Permission error: socket not admitted: %s", skt)
              raise HttpException.new HttpStatus::FORBIDDEN
            end
          end


          def tour_admitted(tur)
            # Check remote host
            is_ok = true
            @check_list.each do |chk|
              if chk.admit
                if chk.tour_admitted(tur)
                  is_ok = true
                  break
                end
              else
                if !chk.tour_admitted(tur)
                  is_ok = false
                  break
                end
              end
            end

            if !is_ok
              raise HttpException.new(HttpStatus::FORBIDDEN, tur.req.uri)
            end

            if @groups.empty?
              return
            end

            # Check member
            is_ok = false
            if tur.req.remote_user != nil
              @groups.each do |grp|
                if grp.validate(tur.req.remote_user, tur.req.remote_pass)
                  is_ok = true
                  break
                end
              end
            end

            if !is_ok
              tur.res.headers.set(Headers::WWW_AUTHENTICATE, "Basic realm=\"Auth\"")
              raise HttpException.new(HttpStatus::UNAUTHORIZED)
            end
          end


          private
          def parse_value(kv)
            items = kv.value.split(" ")
            type = nil
            match_str = []
            items.length.times do |i|
              if i == 0
                type = items[i]
              else
                match_str.append(items[i])
              end
            end

            if match_str.empty?
              raise ConfigException.new(kv.file_name, kv.line_no, BayMessage.get(:CFG_INVALID_PERMISSION_DESCRIPTION, kv.value))
            end

            permission_manager_list = []
            if type.casecmp?("host")
              match_str.each do |m|
                permission_manager_list.append(HostPermissionMatcher.new(m))
              end
            elsif type.casecmp?("ip")
              match_str.each do |m|
                permission_manager_list.append(IpPermissionMatcher.new(m))
              end
            else
              raise ConfigException.new(kv.file_name, kv.line_no, BayMessage.get(:CFG_INVALID_PERMISSION_DESCRIPTION, kv.value))
            end
            return permission_manager_list
          end
        end
      end
    end
  end
end

