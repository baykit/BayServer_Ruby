require 'baykit/bayserver/bcf/package'
require 'baykit/bayserver/docker/harbor'
require 'baykit/bayserver/docker/base/docker_base'
require 'baykit/bayserver/constants'
require 'baykit/bayserver/config_exception'

require 'baykit/bayserver/common/groups'
require 'baykit/bayserver/util/sys_util'


module Baykit
  module BayServer
    module Docker
      module BuiltIn

        class BuiltInHarborDocker < Baykit::BayServer::Docker::Base::DockerBase
          include Baykit::BayServer::Docker::Harbor # implements

          include Baykit::BayServer
          include Baykit::BayServer::Bcf
          include Baykit::BayServer::Util
          include Baykit::BayServer::Common
          include Baykit::BayServer::Constants

          DEFAULT_MAX_SHIPS = 256
          DEFAULT_SHIP_AGENTS = 0
          DEFAULT_TRAIN_RUNNERS = 8
          DEFAULT_TAXI_RUNNERS = 8
          DEFAULT_WAIT_TIMEOUT_SEC = 120
          DEFAULT_KEEP_TIMEOUT_SEC = 20
          DEFAULT_TOUR_BUFFER_SIZE = 1024 * 1024;  # 1M
          DEFAULT_TRACE_HEADER = false
          DEFAULT_CHARSET = "UTF-8"
          DEFAULT_CONTROL_PORT = -1
          DEFAULT_MULTI_CORE = true
          DEFAULT_GZIP_COMP = false
          DEFAULT_NET_MULTIPLEXER = MULTIPLEXER_TYPE_SPIDER
          DEFAULT_FILE_MULTIPLEXER = MULTIPLEXER_TYPE_SPIDER
          DEFAULT_LOG_MULTIPLEXER = MULTIPLEXER_TYPE_SPIDER
          DEFAULT_CGI_MULTIPLEXER = MULTIPLEXER_TYPE_SPIDER
          DEFAULT_RECIPIENT = RECIPIENT_TYPE_SPIDER
          DEFAULT_PID_FILE = "bayserver.pid"

          # Default charset
          attr :charset

          # Default locale
          attr :locale

          # Number of grand agents
          attr :grand_agents

          # Number of train runners
          attr :train_runners

          # Number of taxi runners
          attr :taxi_runners

          # Max count of watercraft
          attr :max_ships

          # Socket timeout in seconds
          attr :socket_timeout_sec

          # Keep-Alive timeout in seconds
          attr :keep_timeout_sec

          # Internal buffer size of Tour
          attr :tour_buffer_size

          # Trace req/res header flag
          attr :trace_header

          # Trouble docker
          attr :trouble

          # Auth groups
          attr :groups

          # File name to redirect stdout/stderr
          attr :redirect_file

          # Gzip compression flag
          attr :gzip_comp

          # Port number of signal agent
          attr :control_port

          # Multi core flag
          attr :multi_core

          # Multiplexer type of network I/O
          attr :net_multiplexer

          # Multiplexer type of file read
          attr :file_multiplexer

          # Multiplexer type of log output
          attr :log_multiplexer

          # Multiplexer type of CGI input
          attr :cgi_multiplexer

          # Recipient type
          attr :recipient

          # PID file name
          attr :pid_file


          def initialize
            @grand_agents = DEFAULT_SHIP_AGENTS
            @train_runners = DEFAULT_TRAIN_RUNNERS
            @taxi_runners = DEFAULT_TAXI_RUNNERS
            @max_ships = DEFAULT_MAX_SHIPS
            @groups = Groups.new
            @socket_timeout_sec = DEFAULT_WAIT_TIMEOUT_SEC
            @keep_timeout_sec = DEFAULT_KEEP_TIMEOUT_SEC
            @tour_buffer_size = DEFAULT_TOUR_BUFFER_SIZE
            @trace_header = DEFAULT_TRACE_HEADER
            @charset = DEFAULT_CHARSET
            @control_port = DEFAULT_CONTROL_PORT
            @multi_core = DEFAULT_MULTI_CORE
            @gzip_comp = DEFAULT_GZIP_COMP
            @net_multiplexer = DEFAULT_NET_MULTIPLEXER
            @file_multiplexer = DEFAULT_FILE_MULTIPLEXER
            @log_multiplexer = DEFAULT_LOG_MULTIPLEXER
            @cgi_multiplexer = DEFAULT_CGI_MULTIPLEXER
            @recipient = DEFAULT_RECIPIENT
            @pid_file = DEFAULT_PID_FILE
          end

          ######################
          # Implements Docker
          ######################
          def init(bcf, parent)
            super

            if @grand_agents <= 0
              @grand_agents = SysUtil.processor_count()
            end

            if @train_runners <= 0
              @train_runners = 1
            end

            if @max_ships < DEFAULT_MAX_SHIPS
              @max_ships = DEFAULT_MAX_SHIPS
              BayLog.warn(BayMessage.get(:CFG_MAX_SHIPS_IS_TO_SMALL, @max_ships))
            end

            if @net_multiplexer == MULTIPLEXER_TYPE_TAXI ||
               @net_multiplexer == MULTIPLEXER_TYPE_TRAIN ||
               @net_multiplexer == MULTIPLEXER_TYPE_SPIN
              BayLog.warn(
                BayMessage.get(
                  :CFG_NET_MULTIPLEXER_NOT_SUPPORTED,
                  Harbor::get_multiplexer_type_name(@net_multiplexer),
                  Harbor::get_multiplexer_type_name(DEFAULT_NET_MULTIPLEXER)))
              @net_multiplexer = DEFAULT_NET_MULTIPLEXER
            end

            if @file_multiplexer == MULTIPLEXER_TYPE_SPIDER and !SysUtil.support_select_file ||
               @file_multiplexer == MULTIPLEXER_TYPE_SPIN and !SysUtil.support_nonblock_file_read ||
               @file_multiplexer == MULTIPLEXER_TYPE_TRAIN
              BayLog.warn(
                BayMessage.get(
                  :CFG_FILE_MULTIPLEXER_NOT_SUPPORTED,
                  Harbor::get_multiplexer_type_name(@file_multiplexer),
                  Harbor::get_multiplexer_type_name(DEFAULT_FILE_MULTIPLEXER)))
              @file_multiplexer = DEFAULT_FILE_MULTIPLEXER
            end

            if @log_multiplexer == MULTIPLEXER_TYPE_SPIDER and !SysUtil.support_select_file ||
               @log_multiplexer == MULTIPLEXER_TYPE_SPIN and !SysUtil.support_nonblock_file_write ||
               @log_multiplexer == MULTIPLEXER_TYPE_TRAIN
              BayLog.warn(
                BayMessage.get(
                  :CFG_LOG_MULTIPLEXER_NOT_SUPPORTED,
                  Harbor::get_multiplexer_type_name(@log_multiplexer),
                  Harbor::get_multiplexer_type_name(DEFAULT_LOG_MULTIPLEXER)))
              @log_multiplexer = DEFAULT_LOG_MULTIPLEXER
            end

            if @log_multiplexer == MULTIPLEXER_TYPE_SPIN ||
               @log_multiplexer == MULTIPLEXER_TYPE_PIGEON
              BayLog.warn(
                BayMessage.get(
                  :CFG_CGI_MULTIPLEXER_NOT_SUPPORTED,
                  Harbor::get_multiplexer_type_name(@cgi_multiplexer),
                  Harbor::get_multiplexer_type_name(DEFAULT_CGI_MULTIPLEXER)))
              @cgi_multiplexer = DEFAULT_CGI_MULTIPLEXER
            end

            if @net_multiplexer == MULTIPLEXER_TYPE_SPIDER &&
               @recipient != RECIPIENT_TYPE_SPIDER
              BayLog.warn(
                BayMessage.get(
                  :CFG_NET_MULTIPLEXER_DOES_NOT_SUPPORT_THIS_RECIPIENT,
                  Harbor::get_multiplexer_type_name(@net_multiplexer),
                  Harbor::get_recipient_type_name(@recipient),
                  Harbor::get_recipient_type_name(RECIPIENT_TYPE_SPIDER)))
              @recipient = RECIPIENT_TYPE_SPIDER
            end

          end

          def init_docker(dkr)
            if dkr.instance_of?(Trouble)
              @trouble = dkr
            else
              return super
            end
            return true
          end

          def init_key_val(kv)
            case kv.key.downcase
            when "loglevel"
              BayLog.set_log_level(kv.value)
            when "charset"
              @charset = kv.value
            when "locale"
              @locale = kv.value
            when "groups"
              begin
                fname = BayServer.parse_path(kv.value)
                @groups.init(fname)
              rescue IOError => e
                raise ConfigException.new(kv.file_name, kv.line_no, BayMessage.get(:CFG_FILE_NOT_FOUND, kv.value));
              end
            when "trains"
              @train_runners = Integer(kv.value)
            when "taxis", "taxies"
              @taxi_runners = Integer(kv.value)
            when "grandagents"
              @grand_agents = Integer(kv.value)
            when "maxships"
              @max_ships = Integer(kv.value)
            when "timeout"
              @socket_timeout_sec = Integer(kv.value)
            when "keeptimeout"
              @keep_timeout_sec = Integer(kv.value)
            when "tourbuffersize"
              @tour_buffer_size = StringUtil.parse_size(kv.value)
            when "traceheader"
              @trace_header = StringUtil.parse_bool(kv.value)
            when "redirectfile"
              @redirect_file = kv.value
            when "controlport"
              @control_port = kv.value.to_i
            when "multicore"
              @multi_core = StringUtil.parse_bool(kv.value)
            when "gzipcomp"
              @gzip_comp = StringUtil.parse_bool(kv.value)

            when "netmultiplexer"
              begin
                @net_multiplexer = Harbor::get_multiplexer_type(kv.value.downcase)
              rescue => e
                BayLog.error_e(e)
                raise ConfigException.new(kv.file_name, kv.line_no, BayMessage::get(:CFG_INVALID_PARAMETER_VALUE, kv.value))
              end

            when "filemultiplexer"
              begin
                @file_multiplexer = Harbor::get_multiplexer_type(kv.value.downcase)
              rescue => e
                BayLog.error_e(e)
                raise ConfigException.new(kv.file_name, kv.line_no, BayMessage::get(:CFG_INVALID_PARAMETER_VALUE, kv.value))
              end

            when "logmultiplexer"
              begin
                @log_multiplexer = Harbor.get_multiplexer_type(kv.value.downcase)
              rescue => e
                BayLog.error_e(e)
                raise ConfigException.new(kv.file_name, kv.line_no, BayMessage::get(:CFG_INVALID_PARAMETER_VALUE, kv.value))
              end

            when "cgimultiplexer"
              begin
                @cgi_multiplexer = Harbor.get_multiplexer_type(kv.value.downcase)
              rescue => e
                BayLog.error_e(e)
                raise ConfigException.new(kv.file_name, kv.line_no, BayMessage::get(:CFG_INVALID_PARAMETER_VALUE, kv.value))
              end

            when "recipient"
              begin
                @recipient = Harbor.get_recipient_type(kv.value.downcase)
              rescue => e
                BayLog.error_e(e)
                raise ConfigException.new(kv.file_name, kv.line_no, BayMessage::get(:CFG_INVALID_PARAMETER_VALUE, kv.value))
              end

            when "pidfile"
              @pid_file = kv.value
            else
              return false
            end
            true
          end

          #######################
          # Implements Harbor
          #######################

        end
      end
    end
  end
end
