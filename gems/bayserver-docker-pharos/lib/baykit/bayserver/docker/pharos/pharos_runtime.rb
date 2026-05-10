require 'fiddle'
require 'fiddle/closure'
require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/util/http_status'

module Baykit
  module BayServer
    module Docker
      module Pharos

        # Process-singleton libphp.so embedding runtime for PharosDocker.
        #
        # init() runs once on plan parse: dlopen + patch ub_write +
        # php_embed_init (then close the auto-started request).
        #
        # run_script() is called per request from any grand agent thread.
        # First call on a new thread registers it with TSRM via
        # ts_resource_ex(0, NULL). Subsequent calls cycle the per-request
        # engine state via php_request_startup / _shutdown, mirroring
        # php-fpm's per-request boundary.
        #
        # Output path: PHP's echo is streamed directly to
        # tour.res.send_res_content from inside the ub_write upcall via
        # Thread.current[:pharos_req_ctx]. Headers are sent lazily on the
        # first chunk to avoid buffering the full body.
        class PharosRuntime
          # Offsets within sapi_module_struct on 64-bit Linux.
          # Mirror the constants in the Java PharosRuntime.
          NAME_OFFSET     = 0
          UB_WRITE_OFFSET = 48

          # Per-thread mutable context: one lookup per ub_write upcall
          # instead of multiple ThreadLocals, and reused across requests
          # on the same grand agent thread.
          class ReqCtx
            attr_accessor :tour, :headers_sent, :error, :tsrm_registered
            def initialize
              @tour            = nil
              @headers_sent    = false
              @error           = nil
              @tsrm_registered = false
            end
          end

          def initialize(lib_php_path)
            @lib_php_path      = lib_php_path
            @handle            = nil
            # Keep these alive for the process lifetime: both are patched
            # into sapi_module_struct and must not be GC'd.
            @ub_write_closure  = nil
            @fpm_fcgi_name     = nil
          end

          # One-time process bootstrap. Loads libphp, patches ub_write,
          # calls php_embed_init, then closes the auto-started request so
          # each per-request lifecycle is started fresh on its own thread.
          def init
            BayLog.info("PharosRuntime: loading %s", @lib_php_path)

            # RTLD_GLOBAL so libphp symbols are visible to opcache.so
            # (opcache.so is dlopen'd later by libphp from php.ini;
            # without RTLD_GLOBAL it cannot resolve zend_* symbols).
            @handle = Fiddle::Handle.new(
              @lib_php_path,
              Fiddle::Handle::RTLD_LAZY | Fiddle::Handle::RTLD_GLOBAL
            )

            # 1. Patch php_embed_module.{name, ub_write}
            embed_module_addr = @handle['php_embed_module']
            embed_module_size = UB_WRITE_OFFSET + Fiddle::SIZEOF_VOIDP
            embed_module_ptr  = Fiddle::Pointer.new(embed_module_addr, embed_module_size)

            # Spoof name: "embed" -> "fpm-fcgi" so opcache's
            # accel_find_sapi accepts us ("embed" is not on its whitelist).
            @fpm_fcgi_name = Fiddle::Pointer.malloc(9)
            @fpm_fcgi_name[0, 9] = "fpm-fcgi\0"
            embed_module_ptr[NAME_OFFSET, Fiddle::SIZEOF_VOIDP] =
              [@fpm_fcgi_name.to_i].pack('J')

            # Replace ub_write with a Ruby upcall that streams bytes
            # directly to tour.res without staging them in a heap buffer.
            @ub_write_closure = Fiddle::Closure::BlockCaller.new(
              Fiddle::TYPE_LONG,
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG]
            ) do |str_addr, length|
              ub_write_impl(str_addr, length)
            end
            embed_module_ptr[UB_WRITE_OFFSET, Fiddle::SIZEOF_VOIDP] =
              [@ub_write_closure.to_i].pack('J')

            # 2. Resolve C symbols
            @php_embed_init = make_fn(
              @handle['php_embed_init'],
              [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_INT
            )
            @php_request_startup = make_fn(
              @handle['php_request_startup'],
              [],
              Fiddle::TYPE_INT
            )
            @php_request_shutdown = make_fn(
              @handle['php_request_shutdown'],
              [Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_VOID
            )
            @zend_eval_string = make_fn(
              @handle['zend_eval_string'],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_INT
            )
            @ts_resource_ex = make_fn(
              @handle['ts_resource_ex'],
              [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
              Fiddle::TYPE_VOIDP
            )

            # 3. Bring PHP up; close the auto-started request so
            #    per-request boundaries start fresh per thread.
            rc = @php_embed_init.call(0, nil)
            raise "php_embed_init returned #{rc}" unless rc == 0
            @php_request_shutdown.call(nil)

            BayLog.info("PharosRuntime: ready (libphp loaded, SAPI started)")
          end

          # Run a PHP snippet on the current thread. Output is streamed to
          # tour.res via the ub_write upcall as PHP echoes; this method
          # does not return a body buffer.
          #
          # Returns true if any output was produced (= headers were sent),
          # false if PHP wrote nothing (caller should send a 0-byte 200).
          def run_script(tour, php_code, label)
            ctx = thread_ctx
            begin
              # Lazy per-thread TSRM registration: first call on a new
              # grand-agent thread allocates its TLS pool.
              unless ctx.tsrm_registered
                @ts_resource_ex.call(0, nil)
                ctx.tsrm_registered = true
              end

              ctx.tour         = tour
              ctx.headers_sent = false
              ctx.error        = nil

              @php_request_startup.call
              begin
                rc = @zend_eval_string.call(php_code, nil, label)
                BayLog.warn("zend_eval_string returned %d for %s",
                            rc, label) if rc != 0
              ensure
                @php_request_shutdown.call(nil)
              end

              raise ctx.error if ctx.error

              ctx.headers_sent
            ensure
              # Clear per-request fields so a leaked Tour reference does
              # not pin memory between requests. tsrm_registered stays sticky.
              ctx.tour  = nil
              ctx.error = nil
            end
          end

          private

          def thread_ctx
            Thread.current[:pharos_req_ctx] ||= ReqCtx.new
          end

          def make_fn(addr, arg_types, ret_type)
            Fiddle::Function.new(addr, arg_types, ret_type)
          end

          # ub_write target. Called from inside libphp during
          # zend_eval_string when PHP code executes echo or print.
          # Streams the bytes directly to the active tour's response
          # without staging them in a Ruby heap buffer.
          def ub_write_impl(str_addr, length)
            ctx  = Thread.current[:pharos_req_ctx]
            tour = ctx&.tour
            # ub_write fired outside of a request context (e.g. module
            # shutdown). Discard.
            return length if tour.nil?

            begin
              # Lazy header send on the first chunk. Content-Length is
              # unknown up front; BayServer will use chunked / conn-close
              # framing as appropriate.
              unless ctx.headers_sent
                tour.res.headers.status = Baykit::BayServer::Util::HttpStatus::OK
                tour.res.headers.set_content_type("text/html; charset=UTF-8")
                tour.res.set_consume_listener { |_len, _r| }
                tour.res.send_headers(tour.tour_id)
                ctx.headers_sent = true
              end

              bytes = Fiddle::Pointer.new(str_addr, length.to_i)[0, length.to_i]
              tour.res.send_res_content(tour.tour_id, bytes, 0, length.to_i)
              length
            rescue => e
              ctx.error ||= e
              -1
            end
          end
        end
      end
    end
  end
end
