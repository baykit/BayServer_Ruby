Gem::Specification.new do |s|
  s.name        = 'bayserver-docker-wordpress'
  s.version     = '2.2.1'
  s.date        = '2023-08-30'
  s.summary     = "WordPress docker of BayServer"
  s.description = "WordPress docker of BayServer"
  s.authors     = ["Michisuke-P"]
  s.email       = 'michisukep@gmail.com'
  s.homepage    = 'https://baykit.yokohama'
  s.license     = 'MIT'
  s.files       = Dir["LICENSE.BAYKIT", "README.md", "lib/**/*.rb"]
  s.add_dependency "bayserver-core", "=2.2.1"
end

