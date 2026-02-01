require 'baykit/bayserver/util/sys_util'

module Baykit
  module BayServer
    class BayLog
      include Baykit::BayServer::Util

      LOG_LEVEL_TRACE = 0
      LOG_LEVEL_DEBUG = 1
      LOG_LEVEL_INFO = 2
      LOG_LEVEL_WARN = 3
      LOG_LEVEL_ERROR = 4
      LOG_LEVEL_FATAL = 5
      LOG_LEVEL_NAME = ["TRACE", "DEBUG", "INFO ", "WARN ", "ERROR", "FATAL"]

      # class instance variables
      class << self
        attr :log_level
        attr :full_path
      end
      @log_level = LOG_LEVEL_INFO
      @full_path = SysUtil.run_on_rubymine()

      def self.set_log_level(lvl)
        if lvl.casecmp? "trace"
          @log_level = LOG_LEVEL_TRACE
        elsif lvl.casecmp? "debug"
          @log_level = LOG_LEVEL_DEBUG
        elsif lvl.casecmp? "info"
          @log_level = LOG_LEVEL_INFO
        elsif lvl.casecmp? "warn"
          @log_level = LOG_LEVEL_WARN
        elsif lvl.casecmp? "error"
          @log_level = LOG_LEVEL_ERROR
        elsif lvl.casecmp? "fatal"
          @log_level = LOG_LEVEL_FATAL
        else
          warn(BayMessage.get(:INT_UNKNOWN_LOG_LEVEL, lvl))
        end
      end

      def self.info(fmt, *args)
        log(LOG_LEVEL_INFO, 3, nil, fmt, args)
      end

      def self.trace(fmt, *args)
        log(LOG_LEVEL_TRACE, 3, nil , fmt, args)
      end

      def self.debug(fmt, *args)
        log(LOG_LEVEL_DEBUG, 3, nil, fmt, args)
      end

      def self.debug_e(err, fmt=nil, *args)
        log(LOG_LEVEL_DEBUG, 3, err, fmt, args)
      end

      def self.warn(fmt, *args)
        log(LOG_LEVEL_WARN, 3, nil, fmt, args)
      end

      def self.warn_e(err, fmt=nil, *args)
        log(LOG_LEVEL_WARN, 3, err, fmt, args)
      end

      def self.error(fmt, *args)
        log(LOG_LEVEL_ERROR, 3, nil , fmt, args)
      end

      def self.error_e(err, fmt=nil, *args)
        log(LOG_LEVEL_ERROR, 3, err, fmt, args)
      end

      def self.fatal(fmt, *args)
        log(LOG_LEVEL_FATAL, 3, nil , fmt, args)
      end

      def self.fatal_e(err, fmt=nil, *args)
        log(LOG_LEVEL_FATAL, 3, err, fmt, args)
        exit(1)
      end

      def self.log(lvl, stack_idx, err, fmt, args)
        if lvl < @log_level
          return
        end

        #pos = caller[1].split("/")[-1]
        apos = parse_caller(caller[1])
        if(!@full_path)
          apos[0] = File.basename(apos[0])
        end
        pos = "#{apos[0]}:#{apos[1]}"
        #pos = caller[1]

        if fmt != nil
          begin
            if args == nil || args.length == 0
              msg = sprintf("%s", fmt)
            else
              msg = sprintf(fmt, *args)
            end
          rescue => e
            puts(e.class)
            puts(e.message + " " + pos)
            print_exception(e)
            msg = fmt
          end

          print("[#{Time.now}] #{LOG_LEVEL_NAME[lvl]}. #{msg} (at #{pos})\n")
        end

        if err != nil
          if debug_mode? || lvl == LOG_LEVEL_FATAL
            puts(err.class)
            puts(err.message + " " + pos)
            print_exception err
          else
            log(lvl, stack_idx + 1, nil, "%s", err.message)
          end
        end
      end

      def self.debug_mode?
        @log_level <= LOG_LEVEL_DEBUG
        #LOG_LEVEL_TRACE < LOG_LEVEL_INFO
      end

      def self.trace_mode?
        @log_level == LOG_LEVEL_TRACE
      end

      def self.print_exception err
        if err.backtrace != nil
          for s in err.backtrace
            puts "\t" + s
          end
        end
        if err.cause
          puts "Caused by:"
          puts err.cause.message
          print_exception err.cause
        end
      end

      private
      def self.parse_caller(str)
        m = /(.*):(.*):in `(.*)'/.match(str)
        return [m[1], m[2], m[3]]
      end
    end
  end
end
