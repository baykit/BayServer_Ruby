Gem::Specification.new do |s|
  s.name        = 'bayserver-docker-ajp'
  s.version     = '2.2.2'
  s.date        = '2023-09-30'
  s.summary     = "AJP docker of BayServer"
  s.description = "BayServer is one of the high-speed web servers. It operates as a single-threaded, asynchronous server, which makes it exceptionally fast. It also supports multi-core processors, harnessing the full potential of the CPU's capabilities."
  s.authors     = ["Michisuke-P"]
  s.email       = 'michisukep@gmail.com'
  s.homepage    = 'https://baykit.yokohama'
  s.license     = 'MIT'
  s.files       = Dir["LICENSE.BAYKIT", "README.md", "lib/**/*.rb"]
  s.add_dependency "bayserver-core", "=2.2.2"
end

