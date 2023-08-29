require 'rack/handler'
require 'baykit/bayserver/bayserver'
require 'baykit/bayserver/util/string_util'

module Rack
  module Handler
    module BayServer
      include Baykit::BayServer::Util

      class << self
        attr :app
      end
      @app = nil

      ENV_BSERV_HOME = Baykit::BayServer::BayServer::ENV_BSERV_HOME
      ENV_BSERV_PLAN = Baykit::BayServer::BayServer::ENV_BSERV_PLAN

      def self.run(app, **options)

        @app = app

        port = options[:Port]
        host = options[:Host]
        config = options[:config]
        environment = options[:environment]
        access_log = options[:AccessLog]

        # Get bayserver home from environment
        if StringUtil.set? ENV[ENV_BSERV_HOME]
          bserv_home = ENV[ENV_BSERV_HOME]
        else
          raise "Set #{ENV_BSERV_HOME} environment variable"
        end

        # Get bayserver plan from evironment
        if StringUtil.set? ENV[ENV_BSERV_PLAN]
          bserv_plan = ENV[ENV_BSERV_PLAN]
        else
          bserv_plan = "/tmp/rack.plan"
          plan_str = <<EOF
[harbor]
 grandAgents 4

[port #{port}]
 docker http

[city *]
 [town /]
  [club *]
   docker terminal
EOF
          ::File.write(bserv_plan, plan_str)
        end

        Baykit::BayServer::BayServer.init bserv_home, bserv_plan
        Baykit::BayServer::BayServer.start
      end

    end




    register :bayserver, BayServer
  end
end
