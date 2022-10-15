class FormParams
  def call(env)
    qstr = env['QUERY_STRING']
    cont = []

    cont << "<html><body>"

    if !qstr || qstr == ""
      # request has no parameter
      cont << "<form method='get'>"
      cont << "First Name: <input type='text' name='fname'/><br/>"
      cont << "Last Name: <input type='text' name='lname'/><br/>"
      cont << "<input type='submit' value='send'/><br/>"
      cont << "</form>"

    else
      # request has parameters
      qstr.split('&').each do |param|
        cont << "#{param}<br/>"
      end
    end

    cont << "</body></html>"
    [200, { "Content-Type" => "text/html" }, cont]
  end
end
