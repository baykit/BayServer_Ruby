require 'baykit/bayserver/docker/docker'

module Baykit
  module BayServer
    module Docker
      #
      # interface
      #
      module Club
        include Docker # implements

        # Get the file name part of club
        def file_name()
          raise NotImplementedError.new
        end

        # Get the ext (file extension part) of club
        def extension()
          raise NotImplementedError.new
        end

        # Check if file name matches this club
        def matches(fname)
          raise NotImplementedError.new
        end

        # Get charset of club
        def charset
          raise NotImplementedError.new
        end

        # Check if this club decodes PATH_INFO
        def decode_path_info
          raise NotImplementedError.new
        end

        #  Arrive
        def arrive(tur)
          raise NotImplementedError.new
        end

      end
    end
  end
end
