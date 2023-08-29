require 'rack'

class MyBodyProxy < Rack::BodyProxy


  def each(&block)
    @body.each do |body|
      yield body
      sleep 1
    end
  end
end

class UseBodyProxy
  def call(env)

    data = []
    data << "<html><body>"
    5.times do |i|
      str = "Line #{i + 1}<br>\n"
      data << str
    end
    data << "</body></html>"

    [200, { "Content-Type" => "text/html" }, MyBodyProxy.new(data)]
  end
end

