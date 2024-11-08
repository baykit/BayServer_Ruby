require 'fcntl'

require 'baykit/bayserver/util/selector'

module Baykit
  module BayServer
    module Agent
        class AcceptHandler
          include Baykit::BayServer::Agent
          include Baykit::BayServer::Util

          attr :agent
          attr :port_map

          attr :is_shutdown
          attr :ch_count

          def initialize(agent, port_map)
            @agent = agent
            @port_map = port_map
            @ch_count = 0
            @is_shutdown = false
          end

          def on_acceptable(server_skt)
          end

          def on_closed()
            @ch_count -= 1
          end

          def on_busy()
            BayLog.debug("%s AcceptHandler:onBusy", @agent)
            @port_map.keys().each do |ch|
              @agent.selector.unregister(ch)
            end
          end

          def on_free()
            BayLog.debug("%s AcceptHandler:onFree isShutdown=%s", @agent, @is_shutdown)
            if @is_shutdown
              return
            end

            @port_map.keys().each do |ch|
              @agent.selector.register(ch, Selector::OP_READ)
            end
          end

          def server_socket?(skt)
            return @port_map.key?(skt)
          end

          def close_all()
            @port_map.keys.each do |skt|
              BayLog.debug("%s Close server Socket: %s", @agent, skt)
              skt.close()
            end
          end

          def shutdown()
            @is_shutdown = true
            on_busy()
            @agent.wakeup()
          end

        end
    end
  end
end

