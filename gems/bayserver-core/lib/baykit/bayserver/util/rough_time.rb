module Baykit
  module BayServer
    module Util
      # Cheap monotonic timestamp source for hot-path timer / timeout
      # / last-access tracking. Mirrors Java BayServer's RoughTime: a
      # background thread refreshes the cached time every INTERVAL_MS
      # milliseconds; readers just return the cached integer with no
      # syscall and no allocation.
      #
      # Use this in place of `Time.now.tv_sec` / `(Time.now.to_f * 1000).to_i`
      # for any code path where ~100ms time accuracy is acceptable. Do
      # NOT use for log timestamps or anywhere precise wall-clock time
      # is required.
      #
      # MRI thread safety: the class-level @cur_ms write and read are
      # both single-bytecode integer ops, the GVL serialises them. No
      # explicit lock is needed.
      class RoughTime
        INTERVAL_MS = 100

        class << self
          # @cur_ms: cached current time in milliseconds since epoch.
          # @timer_thread: the background thread that refreshes @cur_ms.
        end
        @cur_ms = nil
        @timer_thread = nil

        def self.init
          # Idempotent. Each forked agent process must call this once
          # after the fork (threads do not survive fork in MRI), so we
          # also re-init when @cur_ms exists but the timer thread is
          # nil (= we are in a child process).
          return if @timer_thread && @timer_thread.alive?
          @cur_ms = (Time.now.to_f * 1000).to_i
          @timer_thread = Thread.new do
            interval_sec = INTERVAL_MS / 1000.0
            loop do
              sleep interval_sec
              @cur_ms = (Time.now.to_f * 1000).to_i
            end
          end
        end

        # Current time in milliseconds since epoch. Lazily initialises
        # the timer thread on first call so callers do not have to.
        def self.current_time_millis
          init unless @timer_thread
          @cur_ms
        end

        # Current time in seconds since epoch.
        def self.current_time_secs
          current_time_millis / 1000
        end
      end
    end
  end
end
