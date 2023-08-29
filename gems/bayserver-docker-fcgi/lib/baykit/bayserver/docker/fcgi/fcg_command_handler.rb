module Baykit
  module BayServer
    module Docker
      module Fcgi
        module FcgCommandHandler
          include Baykit::BayServer::Protocol::CommandHandler # implements

          #
          # abstract methods
          #
          #     public abstract NextSocketAction handleBeginRequest(CmdBeginRequest cmd) throws IOException;
          #     public abstract NextSocketAction handleEndRequest(CmdEndRequest cmd) throws IOException;
          #     public abstract NextSocketAction handleParams(CmdParams cmd) throws IOException;
          #     public abstract NextSocketAction handleStdErr(CmdStdErr cmd) throws IOException;
          #     public abstract NextSocketAction handleStdIn(CmdStdIn cmd) throws IOException;
          #     public abstract NextSocketAction handleStdOut(CmdStdOut cmd) throws IOException;
          #

        end
      end
    end
  end
end

