require 'baykit/bayserver/protocol/command_handler'

module Baykit
  module BayServer
    module Docker
      module Ajp
        module AjpCommandHandler
          include Baykit::BayServer::Protocol::CommandHandler  # implements

          # abstract method
          #
          # handle_data(cmd)
          # handle_end_response(cmd)
          # handle_forward_request(cmd)
          # handle_send_body_chunk(cmd)
          # handle_send_headers(cmd)
          # handle_shutdown(cmd)
          # handle_get_body_chunk(cmd)
          # need_data()
          #
        end
      end
    end
  end
end

