require 'baykit/bayserver/util/reusable'
module Baykit
  module BayServer
    module Util
      class ObjectStore
        include Baykit::BayServer::Util::Reusable # implements

        attr :free_list
        attr :active_list
        attr :factory

        def initialize(factory=nil)
          @free_list = {}
          @active_list = {}
          @factory = factory
        end

        def reset()
          if @active_list.length > 0
            BayLog.error("BUG?: There are %d active objects: %s", @active_list.length, @active_list)

            # for security
            @free_list.clear()
            @active_list.clear()
          end
        end

        def rent()
          if @free_list.empty?
            if @factory.instance_of? ObjectFactory
              obj = @factory.create_object()
            else
              # lambda
              obj = @factory.call()
            end
          else
            obj = @free_list.shift()[0]
          end
          if obj == nil
            raise Sink.new()
          end
          @active_list[obj] = true
          return obj
        end

        def Return(obj, reuse=true)
          if @free_list.include?(obj)
            raise Sink.new("This object already returned: " + obj.to_s)
          end

          if !@active_list.include?(obj)
            raise Sink.new("This object is not active: " + obj)
          end

          @active_list.delete(obj)
          if reuse
            @free_list[obj] = true
            obj.reset()
          end
        end

        def print_usage(indent)
          BayLog.info("%sfree list: %d", StringUtil.indent(indent), @free_list.length)
          BayLog.info("%sactive list: %d", StringUtil.indent(indent), @active_list.length)
          if BayLog.debug_mode?
            @active_list.each do |obj|
              BayLog.debug("%s%s", StringUtil.indent(indent+1), obj)
            end
          end
        end
      end
    end
  end
end
