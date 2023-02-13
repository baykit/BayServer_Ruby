require 'baykit/bayserver/bayserver'

new_argv = ARGV.dup
new_argv.insert(0, __FILE__ )
Baykit::BayServer::BayServer.main new_argv