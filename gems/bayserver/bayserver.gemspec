Gem::Specification.new do |s|
  s.name        = 'bayserver'
  s.version     = '2.1.1'
  s.date        = '2023-08-29'
  s.summary     = "BayServer"
  s.description = "BayServer"
  s.authors     = ["Michisuke-P"]
  s.email       = 'michisukep@gmail.com'
  s.homepage    = 'https://baykit.yokohama'
  s.license     = 'MIT'
  s.executables = ['bayserver']
  s.files       = Dir["conf/**/*", "init/**/*"]
  s.add_dependency "bayserver-core", "=2.1.1"
  s.add_dependency "bayserver-docker-ajp", "=2.1.1"
  s.add_dependency "bayserver-docker-cgi", "=2.1.1"
  s.add_dependency "bayserver-docker-fcgi", "=2.1.1"
  s.add_dependency "bayserver-docker-http", "=2.1.1"
  s.add_dependency "bayserver-docker-terminal", "=2.1.1"
  s.add_dependency "bayserver-docker-wordpress", "=2.1.1"
end

