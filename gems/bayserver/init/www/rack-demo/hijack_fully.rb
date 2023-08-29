class HijackFully

  def call(env)

    # Fully hijack the client socket.
    env['rack.hijack'].call
    io = env['rack.hijack_io']
    begin
      io.write("HTTP/1.1 200 OK\r\n")
      io.write("Connection: close\r\n")
      io.write("Content-Type: text/html\r\n")
      io.write("\r\n")
      io.write("<html><body>\n")
      io.write("Fully Hijacked<br>\n")
      5.times do |i|
        print "Write data to hijacked io: #{io.inspect}\n"
        io.write("Line #{i + 1}<br/>\n")
        io.flush
        sleep 1
      end
      io.write("</body></html>")
    ensure
      io.close
    end
    [200, [], []]
  end


end
