require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      #
      # "Barge" is a metaphor for the cache management function.
      #
      # interface
      #
      module Barge
        include Docker # implements

        #
        # "Cargo" is a metaphor for cached data.
        #
        # interface
        #
        module Cargo
          def path
            raise NotImplementedError.new
          end

          def headers
            raise NotImplementedError.new
          end

          def content
            raise NotImplementedError.new
          end

          def length
            raise NotImplementedError.new
          end

          def on_barge?
            raise NotImplementedError.new
          end

          def exceeded?
            raise NotImplementedError.new
          end

          def save_headers(headers)
            raise NotImplementedError.new
          end

          def save_content(bytes, offset, len)
            raise NotImplementedError.new
          end

          def end_save
            raise NotImplementedError.new
          end

          def release_rudder(rudder)
            raise NotImplementedError.new
          end
        end

        # Barge name (path)
        def name
          raise NotImplementedError.new
        end

        # Capacity of the barge. (in mega-bytes)
        def capacity
          raise NotImplementedError.new
        end

        # Get cargo on the barge.
        # Returns: [Cargo, Rudder]
        def get_cargo(tour)
          raise NotImplementedError.new
        end

      end
    end
  end
end
