module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module H2CommandHandler
            include Baykit::BayServer::Protocol::CommandHandler # implements

            def handle_preface(cmd)
              raise NotImplementedError.new
            end

            def handle_data(cmd)
              raise NotImplementedError.new
            end

            def handle_headers(cmd)
              raise NotImplementedError.new
            end

            def handle_priority(cmd)
              raise NotImplementedError.new
            end

            def handle_settings(cmd)
              raise NotImplementedError.new
            end

            def handle_window_update(cmd)
              raise NotImplementedError.new
            end

            def handle_go_away(cmd)
              raise NotImplementedError.new
            end

            def handle_ping(cmd)
              raise NotImplementedError.new
            end

            def handle_rst_stream(cmd)
              raise NotImplementedError.new
            end

            def handle_continuation(cmd)
              raise NotImplementedError.new
            end
          end
        end
      end
    end
  end
end


