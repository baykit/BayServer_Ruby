require 'etc'
require 'pathname'
require 'tmpdir'

require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/bayserver'

module Baykit
  module BayServer
    module Util
      class SysUtil

        def SysUtil.run_on_windows()
          return RUBY_PLATFORM.downcase =~ /mswin(?!ce)|mingw|cygwin|bccwin/
        end

        #
        # We set environment variable "RUBYMINE" to 1 for debugging
        #
        def SysUtil.run_on_rubymine()
          return ENV["RUBYMINE"] == "1"
        end

        def SysUtil.support_fork()
          begin
            pid = fork()
            if pid == nil
              exit(0)
            end
            Process.waitpid(pid)
            return true
          rescue NotImplementedError => e
            if BayLog.debug_mode
              BayLog.warn("fork() failed: %s ", e)
              #BayLog.warn_e(e)
            end
            return false
          end
        end


        def SysUtil.support_select_file()
          File.open(BayServer.bserv_plan) do |f|
            begin
              n = select([f], [], [], 10)
              return true
            rescue IOError => e
              if BayLog.debug_mode
                BayLog.warn("select() failed: %s", e)
                #BayLog.warn_e(e)
              end
              return false
            end
          end
        end


        def SysUtil.support_nonblock_file_read()
          File.open(BayServer.bserv_plan) do |f|
            begin
              f.read_nonblock(1)
              return true
            rescue SystemCallError => e
              if BayLog.debug_mode
                BayLog.warn("read_nonblock() failed: %s", e)
                #BayLog.warn_e(e)
              end
              return false
            end
          end
        end

        def SysUtil.support_nonblock_file_write()
          Dir.mktmpdir() do |dir|
            File.open(Pathname(dir) + "test_file", "wb") do |f|
              begin
                f.write_nonblock(1)
                return true
              rescue SystemCallError => e
                if BayLog.debug_mode
                  BayLog.warn("write_nonblock() failed: %s", e)
                  #BayLog.warn_e(e)
                end
                return false
              end
            end
          end
        end


        def SysUtil.support_select_pipe()
          IO.pipe() do |r, w|
            begin
              n = select([r], [w], [], 10)
              return true
            rescue IOError => e
              if BayLog.debug_mode
                BayLog.warn("select() failed: %s", e)
                #BayLog.warn_e(e)
              end
              return false
            end
          end
        end


        def SysUtil.support_nonblock_pipe_read()
          IO.pipe() do |r, w|
            w.write("abcd")
            begin
              r.read_nonblock(1)
              return true
            rescue SystemCallError => e
              if BayLog.debug_mode
                BayLog.warn("read_nonblock() failed: %s", e)
                #BayLog.warn_e(e)
              end
              return false
            end
          end
        end

        def SysUtil.pid()
          return $$
        end

        def SysUtil.processor_count()
          return Etc.nprocessors
        end

        def SysUtil.support_unix_domain_socket_address()
          return !SysUtil.run_on_windows()
        end

      end
    end
  end
end