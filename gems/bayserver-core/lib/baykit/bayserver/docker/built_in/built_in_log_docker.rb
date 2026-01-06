require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/lifecycle_listener'
require 'baykit/bayserver/agent/multiplexer/plain_transporter'
require 'baykit/bayserver/common/rudder_state'
require 'baykit/bayserver/rudders/io_rudder'
require 'baykit/bayserver/docker/built_in/write_file_taxi'
require 'baykit/bayserver/docker/log'
require 'baykit/bayserver/docker/built_in/log_items'
require 'baykit/bayserver/util/string_util'

module Baykit
  module BayServer
    module Docker
        module BuiltIn
          class BuiltInLogDocker < Baykit::BayServer::Docker::Base::DockerBase
            include Baykit::BayServer::Docker::Log # implements

            include Baykit::BayServer::Docker
            include Baykit::BayServer::Util
            include Baykit::BayServer::Bcf
            include Baykit::BayServer::Agent
            include Baykit::BayServer::Common

            class LoggerInfo
              attr_accessor :file_name
              attr_accessor :file_size
              attr_accessor :rudder
              attr_accessor :multiplexer
              attr_accessor :rudder_state
            end

            class AgentListener
              include Baykit::BayServer::Agent::Multiplexer
              include Baykit::BayServer::Agent::LifecycleListener  # implements
              include Baykit::BayServer::Agent
              include Baykit::BayServer::Rudders

              attr :log_docker

              def initialize(dkr)
                @log_docker = dkr
              end

              def add(agt_id)
                info = LoggerInfo.new()
                info.file_name = "#{@log_docker.file_prefix}_#{agt_id}.#{@log_docker.file_ext}"
                info.file_size = 0

                if ::File.exist?(info.file_name)
                  info.file_size = ::File.size(info.file_name)
                end
                agt = GrandAgent.get(agt_id)

                begin
                  f = File.open(info.file_name, "a")
                rescue => e
                  BayLog.fatal(BayMessage.get(:INT_CANNOT_OPEN_LOG_FILE, info.file_name))
                  BayLog.fatal_e(e);
                end

                rd = IORudder.new(f)

                case BayServer::harbor.log_multiplexer
                when Harbor::MULTIPLEXER_TYPE_TAXI
                  mpx = agt.taxi_multiplexer

                when Harbor::MULTIPLEXER_TYPE_SPIN
                  mpx = agt.spin_multiplexer

                when Harbor::MULTIPLEXER_TYPE_SPIDER
                  mpx = agt.spider_multiplexer

                when Harbor::MULTIPLEXER_TYPE_JOB
                  mpx = agt.job_multiplexer

                else
                  raise Sink.new
                end

                info.multiplexer = mpx
                info.rudder = rd

                @log_docker.loggers[agt_id] = info
              end


              def remove(agt_id)
                info = @log_docker.loggers[agt_id]
                rd = info.rudder
                info.multiplexer.req_close(rd)
                @log_docker.loggers[agt_id] = nil
              end
            end


            class << self
              # Mapping table for format
              attr :log_item_map
            end

            # Log send_file name parts
            attr :file_prefix
            attr :file_ext

            # Log format
            attr :format

            # Log items
            attr :log_items

            attr :loggers

            def initialize
              @format = nil
              @log_items = []
              @loggers = {}
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

              log_dir = File.dirname(@file_prefix)
              if !File.directory?(log_dir)
                Dir.mkdir(log_dir)
              end

              # Parse format
              compile(@format, @log_items, elm.file_name, elm.line_no)

              GrandAgent.add_lifecycle_listener(AgentListener.new(self));
            end

            def init_key_val(kv)
              case kv.key.downcase
              when "format"
                @format = kv.value

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
                info = @loggers[tour.ship.agent_id]
                if info.rudder_state == nil
                  info.rudder_state = RudderStateStore.get_store(tour.ship.agent_id).rent()
                  info.rudder_state.init(info.rudder)
                  info.rudder_state.bytes_wrote = info.file_size
                  info.multiplexer.add_rudder_state(info.rudder, info.rudder_state)
                end

                info.multiplexer.req_write(
                  info.rudder,
                  sb,
                  nil,
                  "log"
                )
              end
            end

            private


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
