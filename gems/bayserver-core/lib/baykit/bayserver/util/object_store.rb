require 'baykit/bayserver/util/reusable'
require 'baykit/bayserver/util/object_factory'
require 'baykit/bayserver/bay_log'
module Baykit
  module BayServer
    module Util
      class ObjectStore
        include Baykit::BayServer::Util::Reusable # implements

        attr :free_list
        attr :active_list
        attr :factory

        # Array-backed free_list. The original Hash-based design used
        # Hash#shift / Hash#include? / Hash#delete / Kernel#hash on the
        # hot path; replacing with Array pop/push made rent O(1).
        #
        # @active_list exists only to power the debug-mode integrity
        # check (already-returned / not-active). Maintaining it in
        # production was a measurable bottleneck (Array#delete is O(n)
        # and Letters / WriteUnits Return at request rate × 5+), so
        # both the push on rent and the delete + include? checks on
        # Return are gated on BayLog.debug_mode?. Production never
        # touches @active_list.
        def initialize(factory=nil)
          @free_list = []
          @active_list = []
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
            obj = @free_list.pop
          end
          if obj == nil
            raise Sink.new()
          end
          @active_list.push(obj) if BayLog.debug_mode?
          return obj
        end

        def Return(obj, reuse=true)
          if BayLog.debug_mode?
            if @free_list.include?(obj)
              raise Sink.new("This object already returned: " + obj.to_s)
            end
            if !@active_list.include?(obj)
              raise Sink.new("This object is not active: " + obj.to_s)
            end
            @active_list.delete(obj)
          end
          if reuse
            obj.reset()
            @free_list.push(obj)
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
