require 'baykit/bayserver/docker/fcgi/fcg_type'
require 'baykit/bayserver/docker/fcgi/command/in_out_command_base'


#
#  FCGI spec
#    http://www.mit.edu/~yandros/doc/specs/fcgi-spec.html
#
#   StdIn command format
#    raw data
#
module Baykit
  module BayServer
    module Docker
      module Fcgi
        module Command
          class CmdStdIn < Baykit::BayServer::Docker::Fcgi::Command::InOutCommandBase

            def initialize(req_id, data=nil, start=0, len=0)
              super(FcgType::STDIN, req_id, data, start, len)
            end

            def handle(cmd_handler)
              return cmd_handler.handle_stdin(self)
            end


          end
        end
      end
    end
  end
end
