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
              # Critical section: atomically flip LOADING -> LOADED and
              # snapshot the current @waiters list. After this block
              # try_add_waiter will see LOADED and return false (caller
              # serves from @buf), so no new waiter can be queued past the
              # snapshot.
              #
              # @docker.add_total and the pipe-write notifications run
              # OUTSIDE @lock on purpose: add_total acquires
              # MemBargeDocker.@lock, while get_cargo holds that same lock
              # and reaches us via try_add_waiter -> MemCargo.@lock. Doing
              # add_total inside @lock created an AB-BA deadlock between
              # the file-reader path (this method) and the new-waiter path
              # (get_cargo). pipe.write is also moved out so a slow waiter
              # cannot stall every other request behind MemCargo.@lock.
              waiters_snapshot = nil
              buf_len_to_add = 0

              @lock.synchronize do
                if on_barge?
                  raise "already saved"
                end
                if exceeded?
                  return
                end

                BayLog.debug("%s end save", self)
                @status = LOADED
                buf_len_to_add = @buf_length
                waiters_snapshot = @waiters.dup
                @waiters.clear
              end

              @docker.add_total(buf_len_to_add)

              waiters_snapshot.each do |rd|
                begin
                  BayLog.debug("%s notify waiter", self)
                  rd.write("\x00")
                rescue IOError, SystemCallError => e
                  BayLog.error_e(e)
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

            # Atomically register a waiter only if the cargo is still
            # LOADING. Returns true if the caller will receive a pipe-write
            # notification from end_save; false if the cargo is already
            # LOADED (caller should serve from @buf directly) or EXCEEDED
            # (caller should fall through to the un-cached path).
            #
            # Must be paired with the @lock.synchronize'd end_save: the
            # check + append have to be atomic with end_save's @status =
            # LOADED + @waiters.each, or a waiter registered after each()
            # finishes its iteration but before this method's lock acquires
            # is silently dropped and the client hangs until wrk timeout.
            def try_add_waiter(rd)
              @lock.synchronize do
                return false unless @status == LOADING
                @waiters << rd
                return true
              end
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
                # Reading cgo.status here was racy against end_save: a
                # concurrent end_save could finish iterating @waiters and
                # set status=LOADED between this check and add_waiter,
                # leaving the new waiter without a notification. Use
                # try_add_waiter so MemCargo.@lock guards the
                # status-check + append atomically against end_save's
                # status-set + each. If the cargo turned out to be already
                # LOADED, close the pipe and fall through to the cached
                # path.
                if cgo.status == MemCargo::LOADING
                  BayLog.debug("%s Cannot start tour (file reading)", tour)

                  begin
                    reader, writer = IO.pipe
                  rescue IOError, SystemCallError => e
                    raise Sink.new("Cannot create pipe: %s", e)
                  end
                  source_rd = IORudder.new(reader)
                  source_rd.set_non_blocking
                  wait_rd = IORudder.new(writer)

                  unless cgo.try_add_waiter(wait_rd)
                    # Cargo finished loading while we were creating the
                    # pipe; close both ends and let the caller use the
                    # in-memory copy directly via on_barge?.
                    reader.close rescue nil
                    writer.close rescue nil
                    source_rd = nil
                    tour.res.direct_boarding = false
                  end
                else
                  tour.res.direct_boarding = false  # Don't use OS cache (sendfile API)
                end
              end
              cgo.access
              # LRU access order: re-insert so the most recently used
              # entry sits at the tail. add_total walks @cargo_map in
              # insertion order during eviction, so this turns the
              # walk into oldest-first-by-use rather than oldest-first-
              # by-creation. Mirrors Java's LinkedHashMap(.., accessOrder=true).
              @cargo_map.delete(path)
              @cargo_map[path] = cgo
              return [cgo, source_rd]
            end
          end

          ############################################
          # Private methods
          ############################################

          # Add the size of the newly loaded cargo to the total, then evict
          # old entries (insertion order) until the total falls within capacity.
          # Entries with active waiters are skipped to avoid disrupting
          # in-progress cargo loads.
          def add_total(len)
            @lock.synchronize do
              @total_size += len
              BayLog.trace("%s addTotal=%d", self, @total_size)
              keys = @cargo_map.keys
              keys.each do |path|
                break if @total_size <= @capacity
                eldest = @cargo_map[path]
                if eldest.waiters.empty?
                  BayLog.trace("%s Evict cargo: %s len=%d total=%d", self, path, eldest.length, @total_size)
                  @total_size -= eldest.length
                  @cargo_map.delete(path)
                else
                  BayLog.trace("%s Skip cargo (has waiters): %s", self, path)
                end
              end
            end
          end
        end
      end
    end
  end
end
