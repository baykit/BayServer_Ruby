require "geminabox"

Geminabox.data = File.expand_path("~/.gem-in-a-box")

run Geminabox::Server
