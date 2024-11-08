require 'baykit/bayserver/util/md5_password'
require 'baykit/bayserver/bcf/package'

module Baykit
  module BayServer
    module Common
      class Groups
        include Baykit::BayServer::Bcf

        class Member
          attr :name
          attr :digest

          def initialize(name, digest)
            @name = name
            @digest = digest
          end

          def validate(password)
            if password == nil
              return false
            end

            dig = MD5Password.encode(password)
            return dig == @digest
          end
        end

        class Group
          attr :name
          attr :members
          attr :groups

          def initialize(groups, name)
            @name = name
            @groups = groups
            @members = []
          end

          def add(mem)
            @members << mem
          end

          def validate(mem_name, pass)
            if !@members.include?(mem_name)
              return false
            end

            m = @groups.all_members[mem_name]
            if m == nil
              return false
            end

            return m.validate(pass)
          end
        end

        attr :all_groups
        attr :all_members

        def initialize
          @all_groups = {}
          @all_members = {}
        end

        def init(bcf)
          p = BcfParser.new
          doc = p.parse(bcf)

          doc.content_list.each do |obj|
            if obj.instance_of? BcfElement
              if obj.name.casecmp?("group")
                init_groups(obj)
              elsif obj.name.casecmp?("member")
                init_members(obj)
              end
            end
          end
        end


        def get_group(name)
          return @all_groups[name]
        end


        private
        def init_groups(elm)
          elm.content_list.each do |obj|
            if obj.instance_of? BcfKeyVal
              g = Group.new(self, obj.key)
              @all_groups[obj.key] = g

              obj.value.split(" ").each do |mem_name|
                g.add(mem_name)
              end
            end
          end
        end

        def init_members(elm)
          elm.content_list.each do |obj|
            m = Member.new(obj.key, obj.value)
            @all_members[m.name] = m
          end
        end
      end
    end
  end
end