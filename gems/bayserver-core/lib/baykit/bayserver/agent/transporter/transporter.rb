require 'baykit/bayserver/agent/non_blocking_handler'
require 'baykit/bayserver/agent/channel_listener'
require 'baykit/bayserver/protocol/protocol_exception'
require 'baykit/bayserver/util/reusable'
require 'baykit/bayserver/util/postman'

module Baykit
  module BayServer
    module Agent
        module Transporter
          class Transporter
            include Baykit::BayServer::Agent::ChannelListener # implements
            include Baykit::BayServer::Util::Reusable # implements
            include Baykit::BayServer::Util::Postman  # implements

            include Baykit::BayServer::Protocol
            include Baykit::BayServer::Util

            #
            # Abstract methods
            #
            def secure()
              raise NotImplementedError.new
            end

            def handshake_nonblock()
              raise NotImplementedError.new
            end

            def handshake_finished()
              raise NotImplementedError.new
            end

            attr :data_listener
            attr :infile
            attr :write_queue
            attr :finale
            attr :initialized
            attr :ch_valid
            attr :read_buf
            attr :socket_io
            attr :handshaked
            attr :lock
            attr :capacity
            attr :non_blocking_handler
            attr :write_only

            def initialize(server_mode, bufsiz, trace_ssl, write_only = false)
              @server_mode = server_mode
              @write_queue = []
              @lock = ::Monitor.new()
              @capacity = bufsiz
              @read_buf = StringUtil.alloc(bufsiz)
              @trace_ssl = trace_ssl
              reset()
              @write_only = write_only
            end

            def to_s()
              return "tpt[#{@data_listener.to_s}]"
            end


            ######################################################
            # Implements Reusable
            ######################################################
            def reset()

              # Check write queue
              if !@write_queue.empty?
                raise Sink.new("Write queue is not empty")
              end

              @finale = false
              @initialized = false
              @ch = nil
              set_valid(false)
              @handshaked = false
              @socket_io = nil
              @read_buf.clear()
              @write_only = false
            end

            ######################################################
            # Implements Postman
            ######################################################

            def post(buf, adr, tag, &lisnr)
              check_initialized()

              BayLog.debug("%s post: %s len=%d", self, tag, buf.length)


            end

            ######################################################
            # Implements Valve
            ######################################################

            def open_valve()
              BayLog.debug("%s resume", self)
              @channel_handler.ask_to_read(@ch)
            end

            def abort()
              BayLog.debug("%s abort", self)
              @channel_handler.ask_to_close(@ch)
            end

            def zombie?()
              return @ch != nil && !@ch_valid
            end


            ######################################################
            # Implements ChannelListener
            ######################################################

            def on_readable(chk_ch)
              check_channel(chk_ch)
            end

            def on_writable(chk_ch)
              check_channel(chk_ch)

              BayLog.trace("%s Writable", self)

              if !@handshaked
                begin
                  handshake_nonblock
                  BayLog.debug("#{@ship} Handshake done")
                  @handshaked = true
                rescue IO::WaitReadable => e
                  BayLog.debug("#{@ship} Handshake status: read more")
                  return NextSocketAction::READ
                rescue IO::WaitWritable => e
                  BayLog.debug("#{@ship} Handshake status: write more")
                  return NextSocketAction::CONTINUE
                rescue StandardError => e
                  BayLog.error_e(e, " Error on handshaking: %s", self, e);
                  set_valid(false)
                  return NextSocketAction::CLOSE
                end
              end

              if !@ch_valid
                return NextSocketAction::CLOSE
              end

              empty = false
              while true
                #BayLog.debug "#{self} Send queue len=#{@write_queue.length}"
                wunit = nil
                @lock.synchronize do
                  if @write_queue.empty?
                    empty = true
                    break
                  end
                  wunit = @write_queue[0]
                end

                if empty
                  break
                end

                BayLog.debug("%s Try to write: pkt=%s buflen=%d chValid=%s", self, wunit.tag, wunit.buf.length, @ch_valid)

                if @ch_valid && wunit.buf.length > 0
                  begin
                    len = write_nonblock(wunit.buf, wunit.adr)
                    wunit.buf[0, len] = ""
                    if wunit.buf.length > 0
                      # Data remains
                      break
                    end
                  rescue IO::WaitWritable => e
                    BayLog.debug_e(e, "%s Write will be pended", self)
                    break
                  end
                end

                # packet send complete
                wunit.done()

                @lock.synchronize do
                  @write_queue.delete_at(0)
                  empty = @write_queue.empty?
                end

                if empty
                  break
                end
              end

              if empty
                if @finale
                  BayLog.trace("%s finale return Close", self)
                  state = NextSocketAction::CLOSE
                elsif @write_only
                  state = NextSocketAction::SUSPEND
                else
                  state = NextSocketAction::READ # will be handled as "Write Off"
                end
              else
                state = NextSocketAction::CONTINUE
              end

              return state
            end


            def on_connectable(chk_ch)
              check_channel(chk_ch)
              BayLog.trace("%s onConnectable", self)

              # check connected
              begin
                buf = ""
                @ch.syswrite(buf)
              rescue => e
                BayLog.error("Connect failed: %s", e)
                return NextSocketAction::CLOSE
              end

              return @data_listener.notify_connect()
            end

            def check_timeout(chk_ch, duration)
              check_channel(chk_ch)

              return @data_listener.check_timeout(duration)
            end

            def on_error(chk_ch, e)
              check_channel(chk_ch)
              BayLog.trace("%s onError: %s", self, e)

              begin
                raise e
              rescue OpenSSL::SSL::SSLError => e
                if @trace_ssl
                  BayLog.error_e(e, "%s SSL Error: %s", self, e)
                else
                  BayLog.debug_e(e, "%s SSL Error: %s", self, e)
                end
              rescue => e
                BayLog.error_e(e)
              end
            end

            def on_closed(chk_ch)
              begin
                check_channel(chk_ch)
              rescue => e
                BayLog.error_e(e)
                return
              end

              set_valid(false)

              @lock.synchronize do
                # Clear queue
                @write_queue.each do |write_unit|
                  write_unit.done()
                end
                @write_queue.clear()
              end
              @data_listener.notify_close()
            end

            def flush()
              check_initialized()

              BayLog.debug("%s flush", self)

              if @ch_valid
                empty = false
                @lock.synchronize do
                  empty = @write_queue.empty?
                end

                if !empty
                  BayLog.debug("%s flush->askToWrite", self)
                  @channel_handler.ask_to_write(@ch)
                end
              end
            end

            def post_end()
              check_initialized()

              BayLog.debug("%s postEnd vld=%s", self, self.ch_valid)

              # setting order is QUITE important  finalState->finale
              @finale = true

              if @ch_valid
                empty = nil
                @lock.synchronize do
                  empty = @write_queue.empty?
                end

                if !empty
                  BayLog.debug("%s Tpt: sendEnd->askToWrite", self)
                  @channel_handler.ask_to_write(@ch)
                end
              end
            end

            protected
            def check_channel(chk_ch)
              if chk_ch != @ch
                raise Sink.new("Invalid transporter instance (ship was returned?): #{chk_ch}")
              end
            end

            def check_initialized
              if !@initialized
                raise Sink.new("Illegal State")
              end
            end

            def set_valid(valid)
              @ch_valid = valid
            end

          end
        end
    end
  end
end

