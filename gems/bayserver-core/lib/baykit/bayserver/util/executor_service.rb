
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

          def run
            while true
              tsk = @que.deq
              BayLog.debug("%s Start task on: %s", tsk, @name)
              tsk.run
              BayLog.debug("%s End task on: %s", tsk, @name)
            end
          end

          def to_s
            @name
          end
        end

        MAX_LEN_PER_EXECUTOR = 32

        attr :que
        attr :count
        attr :max_queue_len
        attr :name

        def initialize(name, count)
          @que = Thread::Queue.new
          @count = count
          @max_queue_len = MAX_LEN_PER_EXECUTOR * count
          @name = name

          count.times do |i|
            started = false
            Thread.new do
              started = true
              id = i + 1
              th_name = "Executor[#{name}]##{id}"
              Thread.current.name = th_name
              e = Executor.new @que, id, th_name
              e.run
            end
            while !started
              sleep(0.01)
            end
          end
        end

        def to_s()
          return "ExecutorService[#{@name}]"
        end

        # post task
        def submit(tsk)
          BayLog.debug("%s Submit: task=%s (qlen=%d/%d)", self, tsk, @que.length, @max_queue_len)
          if @que.length > @max_queue_len
            raise IOError("Task queue is full (>_<)")
          end
          @que.enq(tsk)
        end
      end
    end
  end
end