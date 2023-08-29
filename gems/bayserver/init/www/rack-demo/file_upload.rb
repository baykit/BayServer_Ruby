
class FileUpload
  def call(env)

    if env['REQUEST_METHOD'] == "GET"
      # Print form when request method is 'GET'
      cont = []
      cont << "<html><body>"
      cont << "<form method='post'  enctype='multipart/form-data' >"
      cont << "Message: <input type='text' name='message'/><br/>"
      cont << "File: <input type='file' name='file'/><br/>"
      cont << "<input type='submit' value='send'/><br/>"
      cont << "</form>"
      cont << "</body></html>"

    else
      cont_type = env['CONTENT_TYPE']
      p = cont_type.index("boundary=")
      boundary = "--" + cont_type[p + 9 .. nil]

      io = env["rack.input"]
      cont_len = env['CONTENT_LENGTH'].to_i
      req_cont = nil
      if cont_len > 0
        req_cont = io.read(cont_len)
      end

      p "#{io}"
      io.rewind()

      parts = {}
      items = req_cont.split(boundary)
      items.each do |item|
        item.strip!
        io = StringIO.new(item)
        part = {}
        while true
          begin
            line = io.readline().strip()
          rescue EOFError => e
            break
          end

          if line == ""
            break
          end
          p = line.index(":")
          if p
            name = line[0 .. (p-1)].strip()
            value = line[p+1 .. nil].strip()
            p "#{name}=#{value}"
            if name.casecmp?("Content-Disposition")
              value_items = value.split(";")
              value_items.each do |value_item|
                value_item.strip!
                p = value_item.index("=")
                if p
                  value_item_name = value_item[0 .. (p-1)]
                  value_item_value = value_item[p+2 .. -2]
                  p " #{value_item_name}=#{value_item_value}"
                  if value_item_name
                    part[value_item_name] = value_item_value
                  end
                end
              end
            end
          end
        end

        if part.keys.length > 0
          part["body"] = io.read(item.length)
          parts[part["name"]] = part
        end
      end

      message = parts["message"]["body"]
      file_name = File.expand_path(parts["file"]["filename"])
      file_cont = parts["file"]["body"]

      File.open(file_name, "wb") do |f|
        f.write(file_cont)
      end

      env["rack.input"].rewind()
      cont = []
      cont << "<html><body>"
      cont << "Uploaded<br>"
      cont << "Mesasge:#{message}<br>"
      cont << "FileName:#{file_name}<br>"
      cont << "</body></html>"

    end
    [200, { "Content-Type" => "text/html" }, cont]
  end
end
