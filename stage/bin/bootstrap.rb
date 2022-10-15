require "pathname"

bserv_home = ENV["BSERV_HOME"]
if bserv_home == nil
    base_dir = File.dirname(File.expand_path(__FILE__))
    bserv_home = File.dirname(base_dir)
    ENV["BSERV_HOME"] = bserv_home
end

core = Pathname(bserv_home).join('lib').join('core')
$LOAD_PATH.push(core.to_s())

docker = Pathname.new(bserv_home).join('lib').join('docker')

if File.directory?(docker.to_s)
    Dir.foreach(docker.to_s) do |f|
        d = docker.join(f)
        $LOAD_PATH.push(d.to_s)
    end
end

require 'baykit/bayserver/bayserver'
Baykit::BayServer::BayServer.main ARGV
