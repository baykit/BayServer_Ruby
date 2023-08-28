require 'baykit/bayserver/docker/fcgi/fcg_type'

#
#  FCGI spec
#    http://www.mit.edu/~yandros/doc/specs/fcgi-spec.html
#
#   StdErr command format
#    raw data
#

module Baykit
  module BayServer
    module Docker
      module Fcgi
        module Command
          class CmdStdErr < InOutCommandBase

            def initialize(req_id)
              super(FcgType::STDERR, req_id)
            end

            def handle(cmd_handler)
              return cmd_handler.handle_stderr(self)
            end

          end
        end
      end
    end
  end
end
