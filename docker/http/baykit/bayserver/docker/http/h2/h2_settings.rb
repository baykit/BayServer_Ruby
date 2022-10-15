module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2Settings

            DEFAULT_HEADER_TABLE_SIZE = 4096
            DEFAULT_ENABLE_PUSH = true
            DEFAULT_MAX_CONCURRENT_STREAMS = -1
            DEFAULT_MAX_WINDOW_SIZE = 65535
            DEFAULT_MAX_FRAME_SIZE = 16384
            DEFAULT_MAX_HEADER_LIST_SIZE = -1

            attr_accessor :header_table_size
            attr_accessor :enable_push
            attr_accessor :max_concurrent_streams
            attr_accessor :initial_window_size
            attr_accessor :max_frame_size
            attr_accessor :max_header_list_size

            def initialize
              reset
            end

            def reset
              @header_table_size = DEFAULT_HEADER_TABLE_SIZE
              @enable_push = DEFAULT_ENABLE_PUSH
              @max_concurrent_streams = DEFAULT_MAX_CONCURRENT_STREAMS
              @initial_window_size = DEFAULT_MAX_WINDOW_SIZE
              @max_frame_size = DEFAULT_MAX_FRAME_SIZE
              @max_header_list_size = DEFAULT_MAX_HEADER_LIST_SIZE
            end
            
          end
        end
      end
    end
  end
end


