require 'baykit/bayserver/agent/transporter/data_listener'
require 'baykit/bayserver/protocol/packet'
require 'baykit/bayserver/watercraft/boat'

module Baykit
  module BayServer
    module Docker
      module BuiltIn
        class LogBoat < Baykit::BayServer::WaterCraft::Boat
          include Baykit::BayServer::Agent::Transporter::DataListener
          include Baykit::BayServer::Protocol

          class LogPacket < Packet
            def initialize(data)
              super(0, 0, data.length)
              new_data_accessor().put_string(data)
            end
          end

          attr :file_name
          attr :postman

          def initialize()
            super
          end

          def to_s()
            return "lboat##{@boart_id}/#{@object_id} file=#{@file_name}";
          end

          ######################################################
          # Implements Reusable
          ######################################################

          def reset()
            @file_name = nil
            @postman = nil
          end

          ######################################################
          # Implements DataListener
          ######################################################

          def notify_close()
            BayLog.info("Log closed: %s", self.file_name)
          end

          ######################################################
          # Custom methods
          ######################################################

          def init(file_name, postman)
            init_boat()
            @file_name = file_name
            @postman = postman
          end

          def log(data)
            if data == nil
              data = ""
            end
            data += CharUtil::LF

            @postman.post(data, file_name)
          end
        end
      end
    end
  end
end

