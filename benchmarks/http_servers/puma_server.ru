run lambda { |env| [200, { "Content-Length" => "12" }, ["Hello World\n"]] }
