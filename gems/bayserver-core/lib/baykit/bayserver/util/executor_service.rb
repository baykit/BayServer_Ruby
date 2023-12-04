
#
# ExecutorService
#   Implementation of thread pool
#
module Baykit
  module BayServer
    module Util
      class ExecutorService

        class Executor

          attr :que
          attr :id
          attr :name

          def initialize(que, id, name)
            @que = que
            @id = id
            @name = name
          end

          def to_s
            @name
          end

          def run
            while true
              block = @que.deq
              if block == nil
                break
              end
              BayLog.debug("Start task on: %s", @name)
              block.call
              BayLog.debug("End task on: %s", @name)
            end
          end

          def shutdown
            @que.pop until @que.empty?
            @que.enq(nil)
          end
        end

        MAX_LEN_PER_EXECUTOR = 32

        attr :que
        attr :count
        attr :max_queue_len
        attr :name
        attr :executors

        def initialize(name, count)
          @que = Thread::Queue.new
          @count = count
          @max_queue_len = MAX_LEN_PER_EXECUTOR * count
          @name = name
          @executors = []

          count.times do |i|
            started = false
            Thread.new do
              started = true
              id = i + 1
              th_name = "Executor[#{name}]##{id}"
              Thread.current.name = th_name
              e = Executor.new @que, id, th_name
              e.run
              @executors << e
            end
            while !started
              sleep(0.01)
            end
          end
        end

        def to_s
          return "ExecutorService[#{@name}]"
        end

        # post task
        def submit(&block)
          BayLog.debug("%s Submit: (qlen=%d/%d)", self, @que.length, @max_queue_len)
          if @que.length > @max_queue_len
            raise IOError("Task queue is full (>_<)")
          end
          @que.enq(block)
        end

        def shutdown
          @executors.each do |exe|
            exe.shutdown
          end
        end
      end
    end
  end
end