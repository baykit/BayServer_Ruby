require 'baykit/bayserver/agent/next_socket_action'
require 'baykit/bayserver/common/read_only_ship'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/reusable'

module Baykit
  module BayServer
    module Docker
      module Cgi
        class CgiStdOutShip < Baykit::BayServer::Common::ReadOnlyShip

          include Baykit::BayServer::Agent
          include Baykit::BayServer::Util

          attr :file_wrote_len

          attr :tour
          attr :tour_id

          attr :remain
          attr :header_reading
          attr :handler

          def initialize
            super
            reset()
          end

          def init_std_out(rd, agent_id, tur, tp, handler)
            init(agent_id, rd, tp)
            @handler = handler
            @tour = tur
            @tour_id = tur.tour_id
            @header_reading = true
          end

          def to_s()
            return "agt##{@agent_id} out_ship#{@ship_id}/#{@object_id}";
          end

          ######################################################
          # implements Reusable
          ######################################################

          def reset()
            @file_wrote_len = 0
            @tour = nil
            @tour_id = 0
            @header_reading = true
            @remain = ""
            @handler = nil
          end

          ######################################################
          # implements ReadOnlyShip
          ######################################################

          def notify_read(buf)
            @file_wrote_len += buf.length
            BayLog.trace("%s read file %d bytes: total=%d", self, buf.length, @file_wrote_len)

            pos = 0
            if @header_reading

              while true
                p = buf.index("\n", pos)

                #BayLog.debug("pos: %d", pos)

                if p == nil
                  break
                end

                line = buf[pos .. p]
                pos = p + 1

                if @remain.length > 0
                  line = @remain + line
                end
                @remain = ""

                line = line.strip()

                #  if line is empty ("\r\n")
                #  finish header reading.
                if StringUtil.empty?(line)
                  @header_reading = false
                  @tour.res.send_headers(@tour_id)
                  break
                else
                  if BayServer.harbor.trace_header()
                    BayLog.info("%s CGI: res header line: %s", tour, line);
                  end

                  sep_pos = line.index(':')
                  if sep_pos != nil
                    key = line[0 .. sep_pos - 1].strip()
                    val = line[sep_pos + 1 .. -1].strip()

                    if key.downcase() == "status"
                      begin
                        val = val.split(" ")[0]
                        @tour.res.headers.status = val.to_i()
                      rescue => e
                        BayLog.error_e(e)
                      end
                    else
                      @tour.res.headers.add(key, val);
                    end
                  end
                end
              end
            end

            available = true

            if @header_reading
              @remain += buf[pos .. -1]
            else
              if buf.length - pos > 0
                available = @tour.res.send_res_content(@tour_id, buf, pos, buf.length - pos);
              end
            end

            @handler.access()
            if available
              return NextSocketAction::CONTINUE;
            else
              return NextSocketAction::SUSPEND;
            end

          end

          def notify_error(e)
            BayLog.debug_e(e, "%s CGI notifyError", self)
          end

          def notify_eof()
            BayLog.debug("%s stdout EOF(^o^)", @tour)
            return NextSocketAction::CLOSE
          end

          def notify_close()
            BayLog.debug("%s stdout notifyClose", @tour)
            @handler.std_out_closed()
          end

          def check_timeout(duration_sec)
            BayLog.debug("%s Check StdOut timeout: dur=%d", @tour, duration_sec)

            if @handler.timed_out()
              # Kill cgi process instead of handing timeout
              BayLog.warn("%s Kill process!: %d", @tour, @handler.pid)
              Process.kill("KILL", @handler.pid)
              return true
            end

            return false
          end

          ######################################################
          # Custom methods
          ######################################################

        end
      end
    end
  end
end


