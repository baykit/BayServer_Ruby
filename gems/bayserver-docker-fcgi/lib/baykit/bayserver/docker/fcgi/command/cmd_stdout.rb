require 'baykit/bayserver/docker/fcgi/fcg_type'

#
#  FCGI spec
#    http://www.mit.edu/~yandros/doc/specs/fcgi-spec.html
#
#   StdOut command format
#    raw data
#

module Baykit
  module BayServer
    module Docker
      module Fcgi
        module Command
          class CmdStdOut < InOutCommandBase

            def initialize(req_id, data = nil, start = nil, len = nil)
              super(FcgType::STDOUT, req_id, data, start, len)
            end

            def handle(cmd_handler)
              return cmd_handler.handle_stdout(self)
            end

          end
        end
      end
    end
  end
end
