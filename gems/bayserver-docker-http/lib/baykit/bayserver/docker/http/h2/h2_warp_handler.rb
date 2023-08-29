require 'baykit/bayserver/docker/warp/package'
require 'baykit/bayserver/protocol/protocol_exception'

module Baykit
  module BayServer
    module Docker
      module Http
        module H2
          class H2WarpHandler < H2ProtocolHandler
            include Baykit::BayServer::Docker::Warp::WarpHandler # implements

            class WarpProtocolHandlerFactory
              include Baykit::BayServer::Protocol::ProtocolHandlerFactory  # implements

              def create_protocol_handler(pkt_store)
                return H2WarpHandler.new(pkt_store)
              end
            end

            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Agent

            attr :analyzer
            attr :cur_stream_id

            def initialize(pkt_store)
              super(pkt_store, false)
            end

            ######################################################
            # Implements Reusable
            ######################################################

            def reset()
              super
              @cur_stream_id = 1
            end

            ######################################################
            # Implements WarpHandler
            ######################################################
            def next_warp_id
              return H1WarpHandler::FIXED_WARP_ID
            end

            def new_warp_data(warp_id)
              return WarpData.new(ship, warp_id)
            end


            def post_warp_headers(tur)
            end

            def send_req_contents(tur, buf, start, len)
            end

            def end_req_contents(tur)
            end

            def verify_protocol(proto)
            end

            ######################################################
            # Implements H2CommandHandler
            ######################################################
            def handle_preface(cmd)
              if BayLog.debug_mode?
                BayLog.debug("#{ship} handle_preface: proto=#{cmd.protocol}")
              end
              raise Sink.new("Illegal State")
            end

            def handle_data(cmd)
              if BayLog.debug_mode?
                BayLog.debug("#{ship} handle_data: stm=#{cmd.stream_id} len=#{cmd.length}")
              end
              raise Sink.new("Illegal State")
            end

            def handle_headers(cmd)
              if BayLog.debug_mode?
                BayLog.debug("#{ship} handle_headers: stm=#{cmd.stream_id} dep=#{cmd.stream_dependency} weight=#{cmd.weight}")
              end

              raise Sink.new("Illegal State")
            end

            def handle_priority(cmd)
              if BayLog.debug_mode?
                BayLog.debug("#{@ship} handle_priority: stmid=#{cmd.stream_id} dep=#{cmd.stream_dependency} weight=#{cmd.weight}")
              end
              raise Sink.new("Illegal State")
            end

            def handle_settings(cmd)
              if BayLog.debug_mode?
                BayLog.debug("#{@ship} handle_settings: stmid=#{cmd.stream_id}")
              end
              raise Sink.new("Illegal State")
            end

            def handle_window_update(cmd)
              if BayLog.debug_mode?
                BayLog.debug("#{ship} handle_window_update: stmid=#{cmd.stream_id} size=#{cmd.window_size_increment}")
              end
              raise Sink.new("Illegal State")
            end

            def handle_go_away(cmd)
              if BayLog.debug_mode?
                BayLog.debug("#{ship} handle_go_away: last_stm=#{cmd.last_stream_id} code=#{cmd.error_code} " +
                               "desc=#{H2ErrorCode.msg.get_message(cmd.error_code.to_i)} " +
                               "debug=#{cmd.debug_data}")
              end
              return NextSocketAction::CLOSE
            end

            def handle_ping(cmd)
              if BayLog.debug_mode?
                BayLog.debug("#{ship} handle_ping: stm=#{cmd.stream_id}")
              end
              raise Sink.new("Illegal State")
            end

            def handle_rst_stream(cmd)
              if BayLog.debug_mode?
                BayLog.debug("#{ship} handle_rst_stream: stm=#{cmd.stream_id} code=#{cmd.error_code} " +
                               "desc=#{H2ErrorCode.msg.get_message(cmd.error_code.to_i)} ")
              end
              return NextSocketAction::CLOSE
            end

            def to_s
              ship.to_s
            end
          end
        end
      end
    end
  end
end

