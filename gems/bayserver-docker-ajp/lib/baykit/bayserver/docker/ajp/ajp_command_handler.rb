require 'baykit/bayserver/protocol/command_handler'

module Baykit
  module BayServer
    module Docker
      module Ajp
        module AjpCommandHandler
          include Baykit::BayServer::Protocol::CommandHandler  # implements

          def handle_data(cmd)
            raise NotImplementedError.new
          end

          def handle_end_response(cmd)
            raise NotImplementedError.new
          end

          def handle_forward_request(cmd)
            raise NotImplementedError.new
          end

          def handle_send_body_chunk(cmd)
            raise NotImplementedError.new
          end

          def handle_send_headers(cmd)
            raise NotImplementedError.new
          end

          def handle_shutdown(cmd)
            raise NotImplementedError.new
          end

          def handle_get_body_chunk(cmd)
            raise NotImplementedError.new
          end

          def need_data()
            raise NotImplementedError.new
          end
        end
      end
    end
  end
end

