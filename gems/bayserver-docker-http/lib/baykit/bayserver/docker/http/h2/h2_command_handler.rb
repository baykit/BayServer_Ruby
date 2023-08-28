module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          module H2CommandHandler
            include Baykit::BayServer::Protocol::CommandHandler # implements

            #
            # abstract methods
            #
            # handle_preface(cmd)
            # handle_data(cmd)
            # handle_headers(cmd)
            # handle_priority(cmd)
            # handle_settings(cmd)
            # handle_window_update(cmd)
            # handle_go_away(cmd)
            # handle_ping(cmd)
            # handle_rst_stream(cmd)
            #
          end
        end
      end
    end
  end
end


