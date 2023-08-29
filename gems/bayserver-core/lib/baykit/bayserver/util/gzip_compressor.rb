require 'zlib'

module Baykit
  module BayServer
    module Util
      class GzipCompressor

        class CompressListener
          # interface
          # def on_compressed(*str)
        end

        class CallbackWriter

          attr :gzip_comp
          attr_accessor :done_listener

          def initialize(gzip_comp)
            @gzip_comp = gzip_comp
            @done_listener = nil
          end

          def write(*str)
            # proc
            str.each do |item|
              @gzip_comp.listener.call(item, 0, item.length, &@done_listener)
            end
          end
        end

        attr :listener
        attr :gout
        attr :cb_writer

        def initialize(comp_lis)
          @listener = comp_lis
          @cb_writer = CallbackWriter.new(self)
          @gout = Zlib::GzipWriter.new(@cb_writer)
        end

        def compress(buf, ofs, len, &lis)
          @cb_writer.done_listener = lis
          @gout.write(buf[ofs .. ofs + len - 1])
          @gout.flush()
        end

        def finish()
          #@gout.finish()
          @gout.close()
        end

      end
    end
  end
end
