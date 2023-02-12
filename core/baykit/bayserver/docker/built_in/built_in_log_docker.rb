require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/transporter/plain_transporter'
require 'baykit/bayserver/agent/transporter/spin_write_transporter'
require 'baykit/bayserver/docker/built_in/write_file_taxi'
require 'baykit/bayserver/docker/log'
require 'baykit/bayserver/docker/built_in/log_items'
require 'baykit/bayserver/docker/built_in/log_boat'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Docker
        module BuiltIn
          class BuiltInLogDocker < Baykit::BayServer::Docker::Base::DockerBase
            include Baykit::BayServer::Docker::Log # implements
            include Baykit::BayServer::Agent::Transporter
            include Baykit::BayServer::Agent
            include Baykit::BayServer::Util

            include Baykit::BayServer::Bcf

            class AgentListener
              include Baykit::BayServer::Agent::GrandAgent::GrandAgentLifecycleListener  # implements
              include Baykit::BayServer::Agent::Transporter

              attr :log_docker

              def initialize(dkr)
                @log_docker = dkr
              end

              def add(agt)
                file_name = "#{@log_docker.file_prefix}_#{agt.agent_id}.#{@log_docker.file_ext}";

                boat = LogBoat.new()

                case @log_docker.log_write_method
                when LOG_WRITE_METHOD_SELECT
                  tp = PlainTransporter.new(false, 0, true)  # write only
                  tp.init(agt.non_blocking_handler, File.open(file_name, "a"), boat)

                when LOG_WRITE_METHOD_SPIN
                  tp = SpinWriteTransporter.new()
                  tp.init(agt.spin_handler, File.open(file_name, "a"), boat)

                when LOG_WRITE_METHOD_TAXI
                  tp = WriteFileTaxi.new()
                  tp.init(File.open(file_name, "a"), boat)

                end

                begin
                  boat.init(file_name, tp)
                rescue IOError => e
                  BayLog.fatal(BayMessage.get(:INT_CANNOT_OPEN_LOG_FILE, file_name));
                  BayLog.fatal_e(e);
                end

                @log_docker.loggers[agt.agent_id] = boat
              end


              def remove(agt)
                @log_docker.loggers.delete(agt.agent_id);
              end
            end


            LOG_WRITE_METHOD_SELECT = 1
            LOG_WRITE_METHOD_SPIN = 2
            LOG_WRITE_METHOD_TAXI = 3
            DEFAULT_LOG_WRITE_METHOD = LOG_WRITE_METHOD_TAXI

            class << self
              # Mapping table for format
              attr :log_item_map
            end

            # Log send_file name parts
            attr :file_prefix
            attr :file_ext

            # Logger for each agent.
            #    Map of Agent ID => LogBoat
            attr :loggers

            # Log format
            attr :format

            # Log items
            attr :log_items

            # Log write method
            attr :log_write_method

            def initialize
              @loggers = {}
              @format = nil
              @log_items = []
              @log_write_method = DEFAULT_LOG_WRITE_METHOD
            end

            def init(elm, parent)
              super
              p = elm.arg.rindex('.')
              if p == nil
                @file_prefix = elm.arg
                @file_ext = ""
              else
                @file_prefix = elm.arg[0, p]
                @file_ext = elm.arg[p+1 .. -1]
              end

              if @format == nil
                raise ConfigException.new(elm.file_name, elm.line_no, BayMessage.get(:CFG_INVALID_LOG_FORMAT, ""))
              end

              if !File.absolute_path?(@file_prefix)
                @file_prefix = BayServer.get_location @file_prefix
              end

              @loggers = Array.new(BayServer.harbor.grand_agents)

              log_dir = File.dirname(@file_prefix)
              if !File.directory?(log_dir)
                Dir.mkdir(log_dir)
              end

              # Parse format
              compile(@format, @log_items, elm.file_name, elm.line_no)

              # Check log write method
              if @log_write_method == LOG_WRITE_METHOD_SELECT and !SysUtil.support_select_file()
                BayLog.warn(BayMessage.get(:CFG_LOG_WRITE_METHOD_SELECT_NOT_SUPPORTED))
                @log_write_method = LOG_WRITE_METHOD_TAXI
              end

              if @log_write_method == LOG_WRITE_METHOD_SPIN and !SysUtil.support_nonblock_file_write()
                BayLog.warn(BayMessage.get(:CFG_LOG_WRITE_METHOD_SPIN_NOT_SUPPORTED))
                @log_write_method = LOG_WRITE_METHOD_TAXI
              end

              GrandAgent.add_lifecycle_listener(AgentListener.new(self));
            end

            def init_key_val(kv)
              case kv.key.downcase
              when "format"
                @format = kv.value
              when "logwritemethod"
                case kv.value.downcase()
                when "select"
                  @log_write_method = LOG_WRITE_METHOD_SELECT
                when "spin"
                  @log_write_method = LOG_WRITE_METHOD_SPIN
                when "taxi"
                  @log_write_method = LOG_WRITE_METHOD_TAXI
                else
                  raise ConfigException.new(kv.file_name, kv.line_no, BayMessage.get(:CFG_INVALID_PARAMETER_VALUE, kv.value))
                end
              else
                return false
              end
              true
            end

            def log(tour)
              sb = StringUtil.alloc(0)
              @log_items.each do |item|
                item = item.get_item(tour).to_s
                if item == nil
                  sb << "-"
                else
                  sb << item
                end
              end

              # If threre are message to write, write it
              if sb.length > 0
                get_logger(tour.ship.agent).log(sb)
              end
            end

            private

            def get_logger(agt)
              return @loggers[agt.agent_id]
            end



            #
            # Compile format pattern
            #
            def compile(str, items, file_name, line_no)
              # Find control code
              pos = str.index('%')
              if pos != nil
                text = str[0, pos]
                items.append(LogItems::TextItem.new(text))
                compile_ctl(str[pos + 1 .. -1], items, file_name, line_no)
              else
                items.append(LogItems::TextItem.new(str))
              end
            end

            #
            # Compile format pattern(Control code)
            #
            def compile_ctl(str, items, file_name, line_no)
              param = nil

              # if exists param
              if str[0] == '{'
                # find close bracket
                pos = str.index '}'
                if pos == nil
                  raise ConfigException.new(file_name, line_no, BayMessage.get(:CFG_INVALID_LOG_FORMAT, @format))
                end

                param = str[1, pos-1]
                str = str[pos + 1 .. -1]
              end

              ctl_char = ""
              error = false

              if str.length == 0
                error = true
              end

              if !error
                # get control char
                ctl_char = str[0, 1]
                str = str[1 .. -1]

                if ctl_char == ">"
                  if str.length == 0
                    error = true
                  else
                    ctl_char = str[0, 1]
                    str = str[1 .. -1]
                  end
                end
              end

              fct = nil
              if !error
                fct = BuiltInLogDocker.log_item_map[ctl_char]
                if fct == nil
                  error = true
                end
              end

              if error
                ConfigException.new(file_name, line_no,
                                    BayMessage.get(:CFG_INVALID_LOG_FORMAT,
                                                   @format + " (unknown control code: '%" + ctl_char + "')"))
              end

              item = fct.new
              item.init(param)
              @log_items.append(item)
              compile(str, items, file_name, line_no)
            end

            def self.make_map
              @log_item_map = {}
              @log_item_map["a"] = LogItems::RemoteIpItem
              @log_item_map["A"] = LogItems::ServerIpItem
              @log_item_map["b"] = LogItems::RequestBytesItem2
              @log_item_map["B"] = LogItems::RequestBytesItem1
              @log_item_map["c"] = LogItems::ConnectionStatusItem
              @log_item_map["e"] = LogItems::NullItem
              @log_item_map["h"] = LogItems::RemoteHostItem
              @log_item_map["H"] = LogItems::ProtocolItem
              @log_item_map["i"] = LogItems::RequestHeaderItem
              @log_item_map["l"] = LogItems::RemoteLogItem
              @log_item_map["m"] = LogItems::MethodItem
              @log_item_map["n"] = LogItems::NullItem
              @log_item_map["o"] = LogItems::ResponseHeaderItem
              @log_item_map["p"] = LogItems::PortItem
              @log_item_map["P"] = LogItems::NullItem
              @log_item_map["q"] = LogItems::QueryStringItem
              @log_item_map["r"] = LogItems::StartLineItem
              @log_item_map["s"] = LogItems::StatusItem
              @log_item_map[">s"] = LogItems::StatusItem
              @log_item_map["t"] = LogItems::TimeItem
              @log_item_map["T"] = LogItems::IntervalItem
              @log_item_map["u"] = LogItems::RemoteUserItem
              @log_item_map["U"] = LogItems::RequestUrlItem
              @log_item_map["v"] = LogItems::ServerNameItem
              @log_item_map["V"] = LogItems::NullItem
            end

            make_map()

          end
      end
    end
  end
end
