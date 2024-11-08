require 'baykit/bayserver/protocol/packet_store'
require 'baykit/bayserver/common/warp_ship'

module Baykit
  module BayServer
    module Common
        class WarpShipStore < Baykit::BayServer::Util::ObjectStore
          include Baykit::BayServer::Protocol
          include Baykit::BayServer::Util
          include Baykit::BayServer::Common

          attr :keep_list
          attr :busy_list

          attr :max_ships
          attr :lock

          def initialize(max_ships)
            super()
            @keep_list = []
            @busy_list = []
            @lock = Mutex.new
            @max_ships = max_ships
            @factory = -> { WarpShip.new() }
          end

          def to_s
            return "warp_ship_store"
          end

          def rent()
            if @max_ships > 0 && count() >= @max_ships
              return nil
            end

            if @keep_list.empty?
              BayLog.debug("rent from Object Store")

              wsip = super()
              if wsip == nil
                return nil
              end
            else
              BayLog.trace("rent from keep list: %s", @keep_list)
              wsip = @keep_list.delete_at(@keep_list.length - 1)
            end

            if wsip == nil
              raise Sink.new("BUG! ship is null")
            end
            @busy_list.append(wsip)

            BayLog.trace(" rent keepList=%s busyList=%s", @keep_list, @busy_list)
            return wsip
          end

          def keep(wsip)
            BayLog.trace("keep: before keepList=%s busyList=%s", @keep_list, @busy_list)

            if !@busy_list.delete(wsip)
              BayLog.error("%s not in busy list", wsip)
            end

            @keep_list.append(wsip)

            BayLog.trace("keep: after keepList=%s busyList=%s", @keep_list, @busy_list)
          end

          def Return(wsip)
            BayLog.trace("Return: before keepList=%s busyList=%s", @keep_list, @busy_list)

            removed_from_keep = @keep_list.delete(wsip)
            removed_from_busy = @busy_list.delete(wsip)
            if !removed_from_keep && !removed_from_busy
              BayLog.error("%s not in both keep list and busy list", wsip)
            end

            super

            BayLog.trace("Return: after keepList=%s busyList=%s", @keep_list, @busy_list)
          end

          def count()
            @keep_list.length + @busy_list.length
          end

          def print_usage(indent)
            BayLog.info("%sWarpShipStore Usage:", StringUtil.indent(indent))
            BayLog.info("%skeepList: %d", StringUtil.indent(indent+1), @keep_list.length())
            if BayLog.debug_mode?
              @keep_list.each do |obj|
                BayLog.debug("%s%s", StringUtil.indent(indent+1), obj)
              end
            end
            BayLog.info("%sbusyList: %d", StringUtil.indent(indent+1), @busy_list.length())
            if BayLog.debug_mode?
              @busy_list.each do |obj|
                BayLog.debug("%s%s", StringUtil.indent(indent+1), obj)
              end
            end
            super
          end
        end
    end
  end
end
