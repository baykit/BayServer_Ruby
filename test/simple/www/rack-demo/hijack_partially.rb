class HijackPartially

  def call(env)

    data = []
    data << "<html><body>"
    5.times do |i|
      str = "Line #{i + 1}<br>\n"
      data << str
    end
    data << "</body></html>"

    len = data.inject(0) {|result, item|  result + item.length}


    response_headers = {}
    response_headers["Content-Type"] = "text/html"
    response_headers["Content-Length"] = len.to_s
    response_headers["rack.hijack"] = lambda do |io|
      # This lambda will be called after the app server has output
      # headers. Here we can output body data at will.
      begin
        data.each do |text|
          p "APP: write rails app data len=#{text.length}"
          io.write(text)
          io.flush
          sleep 1
        end
      ensure
        io.close
      end
    end
    [200, response_headers, []]
  end


end
