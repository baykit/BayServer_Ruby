require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/http_exception'
require 'baykit/bayserver/tours/req_content_handler'
require 'baykit/bayserver/tours/tour'
require 'baykit/bayserver/util/http_status'

module Baykit
  module BayServer
    module Docker
      module Pharos

        # Per-tour content handler: when the request body is fully received,
        # runs the requested .php file via the embedded libphp runtime.
        #
        # The runtime streams PHP's echo output directly to
        # tour.res.send_res_content from inside its ub_write upcall, so
        # the only thing this handler does after dispatching the script is
        # close the response (or, if PHP wrote nothing, send a zero-byte 200).
        class PharosContentHandler
          include Baykit::BayServer::Tours::ReqContentHandler

          include Baykit::BayServer::Util
          include Baykit::BayServer::Tours

          def initialize(tour, file, runtime)
            @tour    = tour
            @file    = file
            @runtime = runtime
          end

          def on_read_req_content(tur, buf, start, len, &lis)
            # Body upload not yet wired into PHP's $_POST.
            BayLog.debug("%s pharos:onReadContent len=%d (ignored)", tur, len)
            tur.req.consumed(tur.tour_id, len, &lis)
          end

          def on_end_req_content(tur)
            BayLog.debug("%s pharos:endContent file=%s", tur, @file)

            # PHP eval text: include the .php file. Single-quoted absolute
            # path; escape backslashes and single-quotes defensively.
            safe_path = @file.to_s.gsub('\\', '\\\\').gsub("'", "\\'")
            script    = "include '#{safe_path}';"

            wrote_anything =
              begin
                @runtime.run_script(tur, script, "pharos:#{tur.req.uri}")
              rescue => e
                BayLog.error(e, "pharos: runScript failed: %s", @file)
                raise HttpException.new(HttpStatus::INTERNAL_SERVER_ERROR,
                  "Pharos execution failed: #{e.message}")
              end

            # PHP produced no output; emit a zero-byte 200 so the tour
            # can complete normally.
            unless wrote_anything
              tur.res.headers.status = HttpStatus::OK
              tur.res.headers.set_content_type("text/html; charset=UTF-8")
              tur.res.headers.set_content_length(0)
              tur.res.set_consume_listener { |_len, _r| }
              tur.res.send_headers(tur.tour_id)
            end
            tur.res.end_res_content(tur.tour_id)
          end

          def on_abort_req(tur)
            BayLog.debug("%s pharos:onAbort", tur)
            true
          end
        end
      end
    end
  end
end
