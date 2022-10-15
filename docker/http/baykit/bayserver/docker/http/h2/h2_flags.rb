module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2Flags
            FLAGS_NONE = 0x0
            FLAGS_ACK = 0x1
            FLAGS_END_STREAM = 0x1
            FLAGS_END_HEADERS = 0x4
            FLAGS_PADDED = 0x8
            FLAGS_PRIORITY = 0x20

            attr :flags

            def initialize(flags=FLAGS_NONE)
              @flags = flags
            end

            def flag?(flag)
              (flags & flag) != 0
            end

            def set_flag(flag, val)
              if val
                @flags |= flag
              else
                @flags &= ~flag
              end
            end

            def ack?()
              flag?(FLAGS_ACK)
            end

            def set_ack(val)
              set_flag(FLAGS_ACK, val)
            end

            def end_stream?
              flag?(FLAGS_END_STREAM)
            end

            def set_end_stream(val)
              set_flag(FLAGS_END_STREAM, val)
            end

            def end_headers?
              flag?(FLAGS_END_HEADERS)
            end

            def set_end_headers(val)
              set_flag(FLAGS_END_HEADERS, val)
            end

            def padded?
              flag?(FLAGS_PADDED)
            end

            def set_padded(val)
              set_flag(FLAGS_PADDED, val)
            end

            def priority?
              flag?(FLAGS_PRIORITY)
            end

            def set_priority(val)
              set_flag(FLAGS_PRIORITY, val)
            end

            def to_s()
              @flags.to_s()
            end

          end
        end
      end
    end
  end
end

