require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      module Harbor
        include Docker

        MULTIPLEXER_TYPE_SPIDER = 1
        MULTIPLEXER_TYPE_SPIN = 2
        MULTIPLEXER_TYPE_PIGEON = 3
        MULTIPLEXER_TYPE_JOB = 4
        MULTIPLEXER_TYPE_TAXI = 5
        MULTIPLEXER_TYPE_TRAIN = 6

        RECIPIENT_TYPE_SPIDER = 1
        RECIPIENT_TYPE_PIPE = 2

        # Default charset 
        def charset
          raise NotImplementedError.new
        end

        # Default locale
        def locale
          raise NotImplementedError.new
        end

        # Number of grand agents
        def grand_agents
          raise NotImplementedError.new
        end

        # Number of train runners
        def train_runners
          raise NotImplementedError.new
        end

        # Number of taxi runners
        def taxi_runners
          raise NotImplementedError.new
        end

        # Max count of ships
        def max_ships
          raise NotImplementedError.new
        end

        # Trouble docker
        def trouble
          raise NotImplementedError.new
        end

        # Socket timeout in seconds
        def socket_timeout_sec
          raise NotImplementedError.new
        end

        # Keep-Alive timeout in seconds
        def keep_timeout_sec
          raise NotImplementedError.new
        end

        # Trace req/res header flag
        def trace_header
          raise NotImplementedError.new
        end

        # Internal buffer size of Tour
        def tour_buffer_size
          raise NotImplementedError.new
        end

        # File name to redirect stdout/stderr
        def redirect_file
          raise NotImplementedError.new
        end

        # Port number of signal agent
        def control_port
          raise NotImplementedError.new
        end

        # Gzip compression flag
        def gzip_comp
          raise NotImplementedError.new
        end

        # Multiplexer of Network I/O
        def net_multiplexer
          raise NotImplementedError.new
        end

        # Multiplexer of File I/O
        def file_multiplexer
          raise NotImplementedError.new
        end

        # Multiplexer of Log output
        def log_multiplexer
          raise NotImplementedError.new
        end

        # Multiplexer of CGI input
        def cgi_multiplexer
          raise NotImplementedError.new
        end

        # Recipient
        def recipient
          raise NotImplementedError
        end

        # PID file name
        def pid_file
          raise NotImplementedError
        end

        # Multi core flag
        def multi_core?
          raise NotImplementedError
        end


        def self.get_multiplexer_type_name(type)
          case type
          when MULTIPLEXER_TYPE_SPIDER
            return "spider"
          when MULTIPLEXER_TYPE_SPIN
            return "spin"
          when MULTIPLEXER_TYPE_PIGEON
            return "pigeon"
          when MULTIPLEXER_TYPE_JOB
            return "job"
          when MULTIPLEXER_TYPE_TAXI
            return "taxi"
          when MULTIPLEXER_TYPE_TRAIN
            return "train"
          else
            return nil
          end
        end

        def self.get_multiplexer_type(type)
          if type != nil
            type = type.downcase
          end

          case type
          when "spider"
            return MULTIPLEXER_TYPE_SPIDER
          when "spin"
            return MULTIPLEXER_TYPE_SPIN
          when "pigeon"
            return MULTIPLEXER_TYPE_PIGEON
          when "job"
            return MULTIPLEXER_TYPE_JOB
          when "taxi"
            return MULTIPLEXER_TYPE_TAXI
          when "train"
            return MULTIPLEXER_TYPE_TRAIN
          else
            raise ArgumentError
          end
        end

        def self.get_recipient_type_name(type)
          case type
          when RECIPIENT_TYPE_SPIDER
            return "spider"
          when RECIPIENT_TYPE_PIPE
            return "pipe"
          else
            return nil
          end
        end

        def self.get_recipient_type(type)
          if type != nil
            type = type.downcase
          end

          case type
          when "spider"
            return RECIPIENT_TYPE_SPIDER
          when "pipe"
            return RECIPIENT_TYPE_PIPE
          else
            raise ArgumentError
          end
        end

      end
    end
  end
end
