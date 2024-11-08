require 'singleton'
require 'socket'

require 'baykit/bayserver/bay_log'
require 'baykit/bayserver/bay_message'
require 'baykit/bayserver/bay_dockers'
require 'baykit/bayserver/version'
require 'baykit/bayserver/mem_usage'
require 'baykit/bayserver/sink'

require 'baykit/bayserver/rudders/io_rudder'

require 'baykit/bayserver/agent/signal/signal_agent'
require 'baykit/bayserver/agent/signal/signal_sender'
require 'baykit/bayserver/agent/signal/signal_sender'
require 'baykit/bayserver/agent/grand_agent'
require 'baykit/bayserver/agent/monitor/grand_agent_monitor'

require 'baykit/bayserver/bcf/package'

require 'baykit/bayserver/train/train_runner'
require 'baykit/bayserver/taxi/taxi_runner'




require 'baykit/bayserver/protocol/protocol_handler_store'

require 'baykit/bayserver/docker/package'
require 'baykit/bayserver/common/inbound_ship_store'
require 'baykit/bayserver/common/warp_ship_store'

require 'baykit/bayserver/util/locale'
require 'baykit/bayserver/util/md5_password'
require 'baykit/bayserver/util/string_util'
require 'baykit/bayserver/util/mimes'
require 'baykit/bayserver/util/reusable'
require 'baykit/bayserver/util/http_status'
require 'baykit/bayserver/util/selector'

require 'baykit/bayserver/common/cities'

module Baykit
  module BayServer

    class BayServer
      include Baykit::BayServer::Bcf
      include Baykit::BayServer::Util
      include Baykit::BayServer::Agent
      include Baykit::BayServer::Train
      include Baykit::BayServer::Taxi
      include Baykit::BayServer::Agent::Signal
      include Baykit::BayServer::Agent::Monitor
      include Baykit::BayServer::Protocol
      include Baykit::BayServer::WaterCraft
      include Baykit::BayServer::Tours
      include Baykit::BayServer::Docker
      include Baykit::BayServer::Docker::Base
      include Baykit::BayServer::Common
      include Baykit::BayServer::Rudders

      ENV_BSERV_HOME = "BSERV_HOME"
      ENV_BSERV_LIB  = "BSERV_LIB"
      ENV_BSERV_PLAN = "BSERV_PLAN"
      ENV_BSERV_LOGLEVEL = "BSERV_LOGLEVEL"

      # define class instance accessor
      class << self
        attr :script_name
        attr :commandline_args
        attr :bserv_home
        attr :bserv_plan
        attr :bserv_lib
        attr :my_host_name
        attr :my_host_addr
        attr :dockers
        attr :software_name
        attr :cities
        attr :ports
        attr :harbor
        attr :anchorable_port_map
        attr :unanchorable_port_map
        attr :rack_app
        attr :derived_port_nos
        attr :monitor_port
      end

      # Initialize class variables
      @plan_str = nil
      @my_host_name = nil
      @my_host_addr = nil
      @dockers = []
      @ports = []
      @harbor = nil
      @any_city = nil
      @cities = Cities.new()
      @anchorable_port_map = {}
      @unanchorable_port_map = {}

      def self.get_version
        return Version::VERSION
      end

      def self.main(args)
        @commandline_args = args
        cmd = nil
        home = ENV[ENV_BSERV_HOME]
        plan = ENV[ENV_BSERV_PLAN]
        mkpass = nil
        log_level = nil
        agt_id = -1
        init = false

        args.each do |arg|
          if arg.casecmp? "-start"
            cmd = nil
          elsif arg.casecmp? "-stop" or arg.casecmp? "-shutdown"
            cmd = SignalAgent::COMMAND_SHUTDOWN
          elsif arg.casecmp? "-restartAgents"
            cmd = SignalAgent::COMMAND_RESTART_AGENTS
          elsif arg.casecmp? "-reloadCert"
            cmd = SignalAgent::COMMAND_RELOAD_CERT
          elsif arg.casecmp? "-memUsage"
            cmd = SignalAgent::COMMAND_MEM_USAGE
          elsif arg.casecmp? "-abort"
            cmd = SignalAgent::COMMAND_ABORT
          elsif arg.casecmp? "-init"
            init = true
          elsif arg.start_with? "-home="
            home = arg[6 .. nil]
          elsif arg.start_with? "-plan="
            plan = arg[6 .. nil]
          elsif arg.start_with? "-mkpass="
            mkpass = arg[8 .. nil]
          elsif arg.start_with? "-loglevel="
            log_level = arg[10 .. nil]
          elsif arg.start_with? "-agentid="
            agt_id = arg[9 .. nil].to_i
          elsif arg.start_with? "-ports="
            @derived_port_nos = arg[7 .. nil].split(",")
          elsif arg.start_with? "-monitor_port="
            @monitor_port = arg[14 .. nil].to_i
          end
        end

        if mkpass
          puts MD5Passwprd.encode(mkpass)
          exit 0
        end

        self.get_home(home)
        self.get_lib()

        if StringUtil.set?(log_level)
          BayLog.set_log_level(log_level)
        end

        if(init)
          self.init()
        else
          self.get_plan(plan)

          if cmd == nil
            BayServer.start(agt_id)
          else
            SignalSender.new().send_command(cmd)
          end
        end

      end

      # Get BayServer Home
      def self.get_home(home)
        if home != nil
          @bserv_home = home
        elsif StringUtil.set? ENV[ENV_BSERV_HOME]
          @bserv_home = ENV[ENV_BSERV_HOME]
        else
          @bserv_home = '.' if StringUtil.empty?(@bserv_home)
        end

        BayLog.debug "BayServer Home: #{@bserv_home}"
      end

      def self.get_plan(plan)

        if plan != nil
          @bserv_plan = plan
        elsif StringUtil.set? ENV[ENV_BSERV_PLAN]
          @bserv_plan = ENV[ENV_BSERV_PLAN]
        else
          @bserv_plan = @bserv_home + '/plan/bayserver.plan' if StringUtil.empty?(@bserv_plan)
        end
        BayLog.debug "BayServer Plan: #{@bserv_plan}"

      end

      def self.get_lib()
        @bserv_lib = ENV[ENV_BSERV_LIB]
        if !File.directory? @bserv_lib
          raise BayException.new("Library directory is not a directory: %s", @bserv_lib)
        end
        BayLog.debug "BayServer Lib: #{@bserv_lib}"
      end

      def self.init()
        init_dir = @bserv_lib + "/init"
        BayLog.debug("init directory: %s", init_dir)
        file_list = Dir.entries(init_dir) - ['.', '..']
        file_list.each do |file|
          FileUtils.cp_r(File.join(init_dir, file), @bserv_home)
        end
      end


      #
      # Start the system
      #
      def self.start(agt_id)
        begin
          BayMessage.init(@bserv_lib + "/conf/messages", Locale.default())

          @dockers = BayDockers.new
          @dockers.init(@bserv_lib + "/conf/dockers.bcf")

          Mimes.init(@bserv_lib + "/conf/mimes.bcf")
          HttpStatus.init(@bserv_lib + "/conf/httpstatus.bcf")

          if @bserv_plan != nil
            load_plan(@bserv_plan)
          end

          if @ports.empty?
            raise BayException.new BayMessage.get(:CFG_NO_PORT_DOCKER)
          end

          redirect_file = @harbor.redirect_file
          if redirect_file != nil
            if !File.absolute_path? redirect_file
              redirect_file = BayServer.bserv_home + "/" + redirect_file
            end

            f = File.open(redirect_file, "a")
            $stdout = f
            $stderr = f
          end
          $stdout.sync = true
          $stderr.sync = true

          # Init stores, memory usage managers
          PacketStore.init()
          InboundShipStore.init()
          ProtocolHandlerStore.init()
          TourStore.init(TourStore::MAX_TOURS)
          MemUsage.init()

          if SysUtil.run_on_rubymine()
            ::Signal.trap(:INT) do
              p "Trap! Interrupted"
              GrandAgent.shutdown_all()
              exit(0)
            end
          end

          BayLog.debug("Command line: %s", @commandline_args.join(" "))

          if agt_id == -1
            print_version()
            @my_host_name = Socket.gethostname
            BayLog.info("Host name    : %s", @my_host_name)
            parent_start()
          else
            child_start(agt_id)
          end

          return

          while not GrandAgentMonitor.monitors.empty?
            sel = Selector.new()
            pip_to_mon_map = {}
            GrandAgentMonitor.monitors.values.each do |mon|
              BayLog.debug("Monitoring pipe of %s", mon)
              sel.register(mon.communication_channel, Selector::OP_READ)
              pip_to_mon_map[mon.communication_channel] = mon
            end
            server_skt = nil
            if SignalAgent.signal_agent
              server_skt = SignalAgent.signal_agent.server_skt
              sel.register(server_skt, Selector::OP_READ)
            end

            selected_map = sel.select(nil)
            selected_map.keys().each do |ch|
              if ch == server_skt
                SignalAgent.signal_agent.on_socket_readable()
              else
                mon = pip_to_mon_map[ch]
                mon.on_readable()
              end
            end
          end

          SignalAgent.term()

        rescue => err
          BayLog.fatal_e(err, "%s", err.message)
        end
      end

      def self.open_ports(anchored_port_map, unanchored_port_map)
        @ports.each do |dkr|
          # open port
          adr = dkr.address()

          if dkr.anchored
            # Open TCP port
            BayLog.debug(BayMessage.get(:MSG_OPENING_TCP_PORT, dkr.host, dkr.port, dkr.protocol))

            if adr.instance_of? String
              adr = Socket.sockaddr_un(adr)
              skt = Socket.new(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
            else
              adr = Socket.sockaddr_in(adr[0], adr[1])
              skt = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
            end
            #if not SysUtil.run_on_windows()
              skt.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
            #end

            begin
              skt.bind(adr)
            rescue SystemCallError => e
              BayLog.error_e(e, BayMessage.get(:INT_CANNOT_OPEN_PORT, dkr.host, dkr.port, e))
              raise e
            end

            @anchorable_port_map[IORudder.new(skt)] = dkr

            skt.listen(0)

            #skt = port_dkr.new_server_socket skt
            anchored_port_map[skt] = dkr
          else
            # Open UDP port
            BayLog.info(BayMessage.get(:MSG_OPENING_UDP_PORT, dkr.host, dkr.port, dkr.protocol()))

            skt = Socket.new(Socket::AF_INET, Socket::SOCK_DGRAM)
            if not SysUtil.run_on_windows()
              skt.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
            end
            begin
              skt.bind(adr)
            rescue SystemCallError => e
              BayLog.error_e(e, BayMessage.get(:INT_CANNOT_OPEN_PORT, dkr.host, dkr.port, e))
              raise e
            end
            unanchored_port_map[skt] = dkr

          end
        end
      end

      def self.parent_start()
        anchored_port_map = {}
        unanchored_port_map = {}


        if @harbor.multi_core
          if !SysUtil.run_on_windows()
            open_ports(anchored_port_map, unanchored_port_map)
          end
        else
          open_ports(anchored_port_map, unanchored_port_map)

          # Thread mode
          GrandAgent.init(
            (1..@harbor.grand_agents).to_a,
            anchored_port_map,
            unanchored_port_map,
            @harbor.max_ships,
            @harbor.multi_core)

          invoke_runners()
        end

        SignalAgent.init(@harbor.control_port)
        GrandAgentMonitor.init(@harbor.grand_agents, anchored_port_map)
        create_pid_file(Process.pid)
        GrandAgentMonitor.join
      end

      def self.child_start(agt_id)

        invoke_runners()

        @anchorable_port_map = {}
        unanchored_port_map = {}

        if(SysUtil.run_on_windows())
         open_ports(@anchorable_port_map, unanchored_port_map)
        else
          @derived_port_nos.each do |no|
            # Rebuild server socket
            skt = Socket.for_fd(no.to_i)
            portDkr = nil

            @ports.each do |p|
              port = skt.local_address.ip_port
              if p.port == port
                portDkr = p
                break
              end
            end

            if portDkr == nil
              BayLog.fatal("Cannot find port docker: %d", portDkr.port)
              exit(1)
            end

            BayLog.debug("agt#%d server port=%d socket=%s(%d)", agt_id, portDkr.port, skt, no)
            @anchorable_port_map[IORudder.new(skt)] = portDkr
          end
        end


        GrandAgent.init([agt_id], @harbor.max_ships)
        agt = GrandAgent.get(agt_id)

        skt= TCPSocket.new("localhost", @monitor_port)
        rd = IORudder.new(skt)

        agt.add_command_receiver(rd)
        agt.run()
      end

      def self.find_city(city_name)
        return @cities.find_city(city_name)
      end

      def self.parse_path(val)
        val = get_location(val)

        if not ::File::exist?(val)
          raise IOError.new("File not found: #{val}")
        end

        return val
      end


      def self.get_location(location)
        if not File::absolute_path? location
          return @bserv_home + File::SEPARATOR + location
        else
          return location
        end
      end


      def self.get_software_name
        if @software_name == nil
          @software_name = "BayServer/" + get_version
        end
        @software_name
      end

      def self.shutdown
        BayLog.warn "Shutdown..."
        exit(0)
      end

      protected
      #
      # Print version information
      #
      def self.print_version

        version = "Version " + get_version()
        while version.length < 28 do
          version = ' ' + version
        end

        puts("        ----------------------")
        puts("       /     BayServer        \\")
        puts("-----------------------------------------------------")
        print(" \\")
        (47 - version.length()).times.each { |i|
          print(" ")
        }
        puts(version + "  /")
        puts("  \\           Copyright (C) 2021 Yokohama Baykit  /")
        puts("   \\                     http://baykit.yokohama  /")
        puts("    ---------------------------------------------")
      end


      def self.load_plan(bserv_plan)
        p = BcfParser.new
        doc = p.parse(bserv_plan);

        doc.content_list.each do |obj|
          if obj.instance_of?(BcfElement)
            dkr = @dockers.create_docker(obj, nil)
            if dkr.kind_of?(Port)
              @ports << dkr
            elsif dkr.kind_of?(Harbor)
              @harbor = dkr
            elsif dkr.kind_of?(City)
              @cities.add(dkr)
            end
          end
        end
      end


      def BayServer.create_pid_file(pid)
        File.open(BayServer.get_location(@harbor.pid_file), "w") do |f|
          f.write(pid.to_s())
        end
      end

      #
      # Run train runners and taxi runners inner process
      #   ALl the train runners and taxi runners run in each process (not thread)
      #
      def self.invoke_runners()
        n = @harbor.train_runners
        TrainRunner.init(n)

        n = @harbor.taxi_runners
        TaxiRunner.init(n)

      end
    end
  end
end
