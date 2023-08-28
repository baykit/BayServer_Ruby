Gem::Specification.new do |s|
  s.name        = 'bayserver'
  s.version     = '0.0.1'
  s.date        = '2023-08-28'
  s.summary     = "BayServer"
  s.description = "BayServer"
  s.authors     = ["Michisuke-P"]
  s.email       = 'michisukep@gmail.com'
  s.homepage    = 'https://baykit.yokohama'
  s.license     = 'MIT'
  s.executables = ['bayserver']
  s.files       = Dir["conf/**/*"]
  s.add_dependency "bayserver-core", "= 0.0.1"
  s.add_dependency "bayserver-docker-ajp", "= 0.0.1"
  s.add_dependency "bayserver-docker-cgi", "= 0.0.1"
  s.add_dependency "bayserver-docker-fcgi", "= 0.0.1"
  s.add_dependency "bayserver-docker-http", "= 0.0.1"
  s.add_dependency "bayserver-docker-terminal", "= 0.0.1"
  s.add_dependency "bayserver-docker-wordpress", "= 0.0.1"
end

