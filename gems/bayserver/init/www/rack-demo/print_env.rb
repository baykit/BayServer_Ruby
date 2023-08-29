class PrintEnv

  def call(env)

    cont = []
    cont << "<html><body>"
    cont << "<table border='1'>"
    env.keys.each do |key|
      cont << "<tr><td>#{key}</td><td>#{env[key]}</td></tr>"
    end
    cont << "</table>"
    cont << "</body></html>"
    [200, { "Content-Type" => "text/html" }, cont]
  end


end
