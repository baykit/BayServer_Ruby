Gem::Specification.new do |s|
  s.name        = 'bayserver'
  s.version     = '2.2.1'
  s.date        = '2023-08-30'
  s.summary     = "BayServer"
  s.description = "BayServer"
  s.authors     = ["Michisuke-P"]
  s.email       = 'michisukep@gmail.com'
  s.homepage    = 'https://baykit.yokohama'
  s.license     = 'MIT'
  s.executables = ['bayserver_rb']
  s.files       = Dir["LICENSE.BAYKIT", "README.md", "conf/**/*", "init/**/*"]
  s.add_dependency "bayserver-core", "=2.2.1"
  s.add_dependency "bayserver-docker-ajp", "=2.2.1"
  s.add_dependency "bayserver-docker-cgi", "=2.2.1"
  s.add_dependency "bayserver-docker-fcgi", "=2.2.1"
  s.add_dependency "bayserver-docker-http", "=2.2.1"
  s.add_dependency "bayserver-docker-terminal", "=2.2.1"
  s.add_dependency "bayserver-docker-wordpress", "=2.2.1"
end

