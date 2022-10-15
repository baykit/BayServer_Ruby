require_relative './form_params'
require_relative './post_form_params'
require_relative './print_env'
require_relative './hijack_partially'
require_relative './hijack_fully'
require_relative './use_body_proxy'
require_relative './file_upload'

class RackDemo


  ITEMS = {
    "print_env"        => [PrintEnv.new, "Print Environment"],
    "form_params"      => [FormParams.new, "Form Params(get)"],
    "post_form_params" => [PostFormParams.new, "Form Params(post)"],
    "hijack_patially"  => [HijackPartially.new, "Partially Hijack"],
    "hijack_fully"     => [HijackFully.new, "Fully Hijack"],
    "use_body_proxy"   => [UseBodyProxy.new, "Use Body Proxy"],
    "file_upload"      => [FileUpload.new, "File Upload"],
  }

  def call(env)
    print_env env

    path = env["PATH_INFO"].split("/").last()
    item = ITEMS[path]
    if item
      item[0].call env
    else
      menu env
    end
  end

  def menu(env)

    cont = []
    cont << "<html><body>"
    cont << "Rack Demos<p>"
    ITEMS.keys.each do |key|
      cont << "<a href=#{key}>#{ITEMS[key][1]}</a><br>"
    end
    cont << "</body></html>"
    [200, { "Content-Type" => "text/html" }, cont]
  end

  def print_env(env)
    env.keys.each do |key|
      p "#{key}=#{env[key]}"
    end
  end
end
