require 'baykit/bayserver/rudders/rudder'
require 'baykit/bayserver/util/simple_buffer'

require 'baykit/bayserver/docker/send_file/file_content'

module Baykit
  module BayServer
    module Docker
      module SendFile
        class FileStore

          class FileContentStatus
            STARTED = 1
            READING = 2
            COMPLETED = 3
            EXCEEDED = 4

            attr :file_content
            attr :status

            def initialize(file_content, status)
              @file_content = file_content
              @status = status
            end
          end

          attr :contents
          attr :limit_bytes
          attr :total_bytes
          attr :lifespan_seconds
          attr :lock

          def initialize(timeout_sec, limit_bytes)
            @lifespan_seconds = timeout_sec
            @limit_bytes = limit_bytes
            @total_bytes = 0
            @contents = {}
            @lock = Mutex.new
          end

          def get(path)
            @lock.synchronize do
              status = 0
              file_content = @contents[path]

              if file_content != nil
                now =  Time.now.to_i

                if file_content.loaded_time + @lifespan_seconds < Time.now.to_i
                  @total_bytes -= file_content.length
                  BayLog.debug("Remove expired content: %s", path)
                  @contents.delete(path)
                  file_content = nil
                else
                  if file_content.is_loaded
                    status = FileContentStatus::COMPLETED
                  else
                    status = FileContentStatus::READING
                  end
                end
              end

              if file_content == nil
                length = File.size(path)
                exceeded = false
                if length <= @limit_bytes
                  if @total_bytes + length > @limit_bytes
                    if !evict()
                      exceeded = true
                    end
                  end
                else
                  exceeded = true
                end

                if exceeded
                  status = FileContentStatus::EXCEEDED
                else
                  file_content = FileContent.new(path, length)
                  @contents[path] = file_content
                  @total_bytes += length
                  status = FileContentStatus::STARTED
                end
              end
              return FileContentStatus.new(file_content, status)

            end
          end

          def evict()
            evict_list = []
            @contents.each do | path, content |
              if content.is_loaded
                next
              end

              if content.loaded_time + @lifespan_seconds < Time.now.to_i
                # Timed out content
                BayLog.debug("Remove expired content: %s", path)
                @total_bytes -= content.length
                evict_list << path
              else
                break
              end
            end

            evict_list.each do | path |
              @contents.delete(path)
            end

            return !evict_list.empty?
          end
        end
      end
    end
  end
end
