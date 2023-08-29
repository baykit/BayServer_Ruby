require 'baykit/bayserver/bay_exception'

module Baykit
  module BayServer

    class ConfigException < BayException
      attr_reader :file_name
      attr_reader :line_no

      def initialize(file_name, line_no, fmt, *args)
        super(fmt, *args)
        @file_name = file_name
        @line_no = line_no
      end

      def message()
        return ConfigException::create_message(super, @file_name, @line_no)
      end

      def self::create_message(msg, fname, line)
        return "#{msg == nil ? "" : msg} #{fname}:#{line}"
      end
    end
  end
end
