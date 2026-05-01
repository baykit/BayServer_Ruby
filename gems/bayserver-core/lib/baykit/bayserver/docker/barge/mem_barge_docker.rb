require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/bayserver'
require 'baykit/bayserver/sink'
require 'baykit/bayserver/docker/barge'
require 'baykit/bayserver/docker/base/docker_base'
require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/util/headers'
require 'baykit/bayserver/util/simple_buffer'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Docker
      module Barge
        class MemBargeDocker < Baykit::BayServer::Docker::Base::DockerBase
          include Baykit::BayServer::Docker::Barge # implements
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util
          include Baykit::BayServer::Rudders

          class MemCargo
            include Baykit::BayServer::Docker::Barge::Cargo # implements
            include Baykit::BayServer::Util

            LOADING = 1
            LOADED = 2
            EXCEEDED = 3

            attr :docker
            attr :path
            attr :buf_length
            attr :status
            attr :buf
            attr :headers
            attr :last_accessed_time_millis
            attr :waiters
            attr :lock

            def initialize(docker, path)
              @docker = docker
              @path = path
              @buf_length = 0
              @status = LOADING
              @buf = SimpleBuffer.new
              @headers = Headers.new
              @last_accessed_time_millis = 0
              @waiters = []
              @lock = Mutex.new
            end

            ############################################
            # Implements Cargo
            ############################################

            def content
              return @buf.bytes
            end

            def length
              return @buf.length
            end

            def on_barge?
              return @status == LOADED
            end

            def exceeded?
              return @status == EXCEEDED
            end

            def save_headers(headers)
              if on_barge?
                raise "already saved"
              end
              if exceeded?
                return
              end

              headers.copy_to(@headers)
            end

            def save_content(bytes, offset, len)
              if on_barge?
                raise "already saved"
              end
              if exceeded?
                return
              end

              BayLog.debug("%s save content len=%d", self, len)
              @buf_length += len

              if @buf_length > BayServer.harbor.max_cargo_size
                BayLog.debug("%s cargo exceeded: len=%d max=%d", self, @buf_length, BayServer.harbor.max_cargo_size)
                @status = EXCEEDED
                @buf.reset
                return
              else
                @buf.put(bytes, offset, len)
              end
            end

            def end_save
              @lock.synchronize do
                if on_barge?
                  raise "already saved"
                end
                if exceeded?
                  return
                end

                BayLog.debug("%s end save", self)
                @status = LOADED
                @docker.add_total(@buf_length)

                @waiters.each do |rd|
                  begin
                    BayLog.debug("%s notify waiter", self)
                    rd.write("\x00")
                  rescue IOError, SystemCallError => e
                    BayLog.error_e(e)
                  end
                end
              end
            end

            def release_rudder(rudder)
              @lock.synchronize do
                @waiters.delete(rudder)
              end
            end

            ############################################
            # Private methods
            ############################################

            def access
              @last_accessed_time_millis = (Time.now.to_f * 1000).to_i
            end

            def expired?
              @waiters.empty? &&
                (Time.now.to_f * 1000).to_i - @last_accessed_time_millis > BayServer.harbor.cargo_lifespan_sec * 1000
            end

            def add_waiter(rd)
              @waiters << rd
            end
          end

          attr :name
          attr :capacity
          attr :total_size
          attr :cargo_map
          attr :lock

          def initialize
            @name = nil
            @capacity = 32 * 1024 * 1024  # 32M bytes
            @total_size = 0
            # Enable "Access Order" (LRU) mode by using a map with access-order tracking.
            # In this mode, the most recently accessed entry moves to the end of the list.
            # (Currently: insertion order, matching the Java implementation.)
            @cargo_map = {}
            @lock = Mutex.new
          end


          def to_s
            return "MemBargeDocker[#{@name}]"
          end

          ###################################################################
          # Implements Docker
          ###################################################################

          def init(elm, parent)
            super
            @name = elm.arg
            if StringUtil.empty?(@name)
              @name = "*"
            end
          end

          ###################################################################
          # Implements DockerBase
          ###################################################################

          def init_key_val(kv)
            case kv.key.downcase
            when "capacity"
              @capacity = StringUtil.parse_size(kv.value)
            else
              return super
            end
            return true
          end

          ############################################
          # Implements Barge
          ############################################

          def get_cargo(tour)
            @lock.synchronize do
              path = tour.req.uri
              cgo = @cargo_map[path]
              source_rd = nil

              if cgo != nil && cgo.waiters.empty? && cgo.expired?
                @total_size -= cgo.length
                @cargo_map.delete(path)
                cgo = nil
              end

              if cgo == nil
                cgo = MemCargo.new(self, path)
                @cargo_map[path] = cgo
                tour.res.direct_boarding = false  # Don't use OS cache (sendfile API)
              else
                if cgo.status == MemCargo::LOADING
                  # Cargo is loading
                  # Wait until cargo is loaded.
                  BayLog.debug("%s Cannot start tour (file reading)", tour)

                  begin
                    reader, writer = IO.pipe
                    source_rd = IORudder.new(reader)
                    source_rd.set_non_blocking
                    wait_rd = IORudder.new(writer)
                  rescue IOError, SystemCallError => e
                    raise Sink.new("Cannot create pipe: %s", e)
                  end
                  cgo.add_waiter(wait_rd)
                else
                  tour.res.direct_boarding = false  # Don't use OS cache (sendfile API)
                end
              end
              cgo.access
              return [cgo, source_rd]
            end
          end

          ############################################
          # Private methods
          ############################################

          def add_total(len)
            @lock.synchronize do
              @total_size += len
              BayLog.debug("%s addTotal=%d", self, @total_size)
              keys = @cargo_map.keys
              keys.each do |path|
                break if @total_size <= @capacity
                eldest = @cargo_map[path]
                BayLog.debug("%s Remove cargo: %s cur total=%d", self, path, @total_size)
                if eldest.waiters.empty?
                  @total_size -= eldest.length
                  @cargo_map.delete(path)
                end
                BayLog.debug("%s cargo removed: total=%d", self, @total_size)
              end
            end
          end
        end
      end
    end
  end
end
