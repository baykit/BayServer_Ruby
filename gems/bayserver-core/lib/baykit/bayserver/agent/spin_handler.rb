
module Baykit
  module BayServer
    module Agent
      class SpinHandler

        module SpinListener
          #
          # interface
          #
          #         NextSocketAction lap(boolean spun[]);
          #         boolean checkTimeout(int durationSec);
          #         void close();
          #
        end

        class ListenerInfo
          attr :listener
          attr :last_access

          def initialize(lis, last_access)
            @listener = lis
            @last_access = last_access
          end
        end


        attr :listeners
        attr :lock
        attr :agent
        attr :spin_count

        def initialize(agt)
          @listeners = []
          @lock = Mutex.new
          @agent = agt
          @spin_count = 0
        end

        def to_s()
          return @agent.to_s()
        end

        def process_data()
          if @listeners.empty?
            return false
          end

          all_spun = true
          remove_list = []
          @listeners.length.downto(1) do |i|
            lis = listeners[i-1].listener
            act, spun = lis.lap()

            case act
            when NextSocketAction::SUSPEND
              remove_list.append(i-1)
            when NextSocketAction::CLOSE
              remove_list.append(i-1)
            when NextSocketAction::CONTINUE
              next
            else
              raise Sink.new()
            end

            @listeners[i].last_access = Time.now.tv_sec()
            all_spun = all_spun & spun
          end

          if all_spun
            @spin_count += 1
            if @spin_count > 10
              sleep(0.01)
            else
              @spin_count = 0
            end
          end

          remove_list.each do |i|
            @lock.synchronize do
              @listeners.delete_at(i)
            end
          end

          return true
        end

        def ask_to_callback(lis)
          BayLog.debug("%s Ask to callback: %s", self, lis)

          found = false
          for ifo in @listeners do
            if ifo.listener == lis
              found = true
              break
            end
          end

          if found
            BayLog.error("Already registered")
          else
            @lock.synchronize do
              @listeners.append(ListenerInfo.new(lis, Time.now.tv_sec))
            end
          end
        end

        def empty?()
          return @listeners.empty?
        end


        def stop_timeout_spins()
          if !@listeners.empty?
            return
          end

          remove_list = []
          @lock.synchronize do
            now = Time.now.tv_sec
            @listeners.length.downto(1) do |i|
              ifo = @listeners[i-1]
              if ifo.listener.check_timeout(int(now - ifo.last_access))
                ifo.listener.close()
                remove_list.append(i)
              end
            end
          end

          remove_list.each do |i|
            @lock.synchronize do
              self.listeners.pop(i)
            end
          end
        end
      end
    end
  end
end

