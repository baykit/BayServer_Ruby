Gem::Specification.new do |s|
  s.name        = 'bayserver-docker-wordpress'
  s.version     = '2.2.0'
  s.date        = '2023-08-29'
  s.summary     = "WordPress docker of BayServer"
  s.description = "WordPress docker of BayServer"
  s.authors     = ["Michisuke-P"]
  s.email       = 'michisukep@gmail.com'
  s.homepage    = 'https://baykit.yokohama'
  s.license     = 'MIT'
  s.files       = Dir.glob("lib/**/*.rb")
  s.add_dependency "bayserver-core", "=2.2.0"
end

