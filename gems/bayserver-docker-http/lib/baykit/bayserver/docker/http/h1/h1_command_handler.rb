
module Baykit
  module BayServer
    module Docker
      module Http
        module H1
          module H1CommandHandler # interface
            include Baykit::BayServer::Protocol::CommandHandler # implements

            def handle_header(cmd)
              raise NotImplementedError.new()
            end

            def handle_content(cmd)
              raise NotImplementedError.new()
            end

            def handle_end_content(cmd)
              raise NotImplementedError.new()
            end

            def finished()
              raise NotImplementedError.new()
            end
          end
        end
      end
    end
  end
end

