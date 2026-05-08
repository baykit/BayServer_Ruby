require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/bayserver'
require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/util/directory_exception'

module Baykit
  module BayServer
    module Tours
      class DirectBoardingStore

        class FileInfo
          attr_accessor :file_name
          attr_accessor :rudder
          attr_accessor :file_length
          attr_accessor :last_access_time

          def initialize(file_name, rd, len)
            @file_name = file_name
            @rudder = rd
            @file_length = len
            access
          end

          def access
            @last_access_time = (Time.now.to_f * 1000).to_i
          end

          def close
            begin
              @rudder.close if @rudder
            rescue IOError => e
              BayLog.error_e(e)
            end
            @rudder = nil
          end
        end

        @@store = nil

        attr :max_cargos

        def initialize(timeout_sec, max_cargos, max_cargo_size)
          @lifespan_milli_sec = timeout_sec * 1000
          @max_cargos = max_cargos
          @max_cargo_size = max_cargo_size
          # Access-order map (LRU). Most recently accessed entry moves to the end.
          @files = {}
          @lock = Mutex.new
        end

        def get(path)
          @lock.synchronize do
            info = @files[path]
            now = (Time.now.to_f * 1000).to_i
            if info != nil && now > info.last_access_time + @lifespan_milli_sec
              BayLog.debug("%d %d %d %d", info.last_access_time, @lifespan_milli_sec, info.last_access_time + @lifespan_milli_sec, now)
              info.close
              @files.delete(path)
              info = nil
            end

            if info == nil
              if File.directory?(path)
                raise Baykit::BayServer::Util::DirectoryException.new
              end

              size = File.size(path)
              max_size = BayServer.harbor.max_direct_boarding_size
              if max_size >= 0 && size > max_size
                info = FileInfo.new(path, nil, size)
              else
                f = File.open(path, "rb")
                rd = Baykit::BayServer::Rudders::IORudder.new(f)
                info = FileInfo.new(path, rd, size)
              end

              @files[path] = info
              evict_eldest
            else
              # LRU: move to end on access
              @files.delete(path)
              @files[path] = info
            end

            info.access
            return info
          end
        end

        def self.get_file_info(path)
          get_store.get(path)
        end

        private

        def self.get_store
          if @@store == nil
            @@store = DirectBoardingStore.new(
              BayServer.harbor.cargo_lifespan_sec,
              BayServer.harbor.max_direct_boardings,
              BayServer.harbor.max_cargo_size)
          end
          return @@store
        end

        def evict_eldest
          while @files.size > @max_cargos
            eldest_path = @files.keys.first
            eldest = @files.delete(eldest_path)
            # Evict the LRU file descriptor and ensure it's closed
            # to avoid OS-level fd leaks.
            eldest.close if eldest
          end
        end

      end
    end
  end
end
