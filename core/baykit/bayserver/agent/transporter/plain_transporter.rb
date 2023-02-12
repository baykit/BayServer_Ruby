require 'baykit/bayserver/agent/transporter/transporter'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/agent/next_socket_action'

module Baykit
  module BayServer
    module Agent
        module Transporter
          class PlainTransporter < Baykit::BayServer::Agent::Transporter::Transporter
            include Baykit::BayServer::Agent
            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Util

            def initialize(server_mode, bufsiz, write_only = false)
              super(server_mode, bufsiz, false, write_only)
            end

            def init(nb_hnd, ch, lis)
              super
              @handshaked = true  # plain socket doesn't need to handshake
            end

            def to_s
              return "tp[#{@data_listener}]"
            end

            ######################################################
            # Implements Transporter
            ######################################################

            def secure()
              return false
            end

            def handshake_nonblock
              raise Sink.new("needless to handshake")
            end

            def read_nonblock()
              #@ch.sysread(@capacity, @read_buf)
              @ch.read_nonblock(@capacity, @read_buf)
              return nil # client address (for UDP)
            end

            def write_nonblock(buf, adr)
              #return @ch.syswrite(buf)
              return @ch.write_nonblock(buf)
            end
          end
        end
    end
  end
end


