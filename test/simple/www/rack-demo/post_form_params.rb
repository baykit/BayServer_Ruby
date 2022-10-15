class PostFormParams
  def call(env)

    cont_len = env['CONTENT_LENGTH'].to_i
    qstr = nil
    if cont_len > 0
      qstr = env["rack.input"].read(cont_len)
    end
    cont = []
    cont << "<html><body>"

    if !qstr || qstr == ""
      # request has no parameter
      cont << "<form method='post'>"
      cont << "First Name: <input type='text' name='fname'/><br/>"
      cont << "Last Name: <input type='text' name='lname'/><br/>"
      cont << "<input type='submit' value='send'/><br/>"
      cont << "</form>"

    else
      # request has parameters
      cont << "Posted parameters:<br/>"
      qstr.split('&').each do |param|
        cont << "#{param}<br/>"
      end
    end

    cont << "</body></html>"
    [200, { "Content-Type" => "text/html" }, cont]
  end
end
