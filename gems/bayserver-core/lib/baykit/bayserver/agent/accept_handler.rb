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
            port_dkr = @port_map[server_skt]

            begin
              client_skt, = server_skt.accept_nonblock
            rescue IO::WaitReadable
              # Maybe another agent get socket
              BayLog.debug("Accept failed (must wait readable)")
              return
            end

            BayLog.debug("Accepted: skt=%d", client_skt.fileno)

            begin
              port_dkr.check_admitted(client_skt)
            rescue => e
              BayLog.error_e(e)
              client_skt.close()
              return
            end

            client_skt.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)

            tp = port_dkr.new_transporter(@agent, client_skt)
            @agent.non_blocking_handler.ask_to_start(client_skt)
            @agent.non_blocking_handler.ask_to_read(client_skt)
            @ch_count += 1
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

