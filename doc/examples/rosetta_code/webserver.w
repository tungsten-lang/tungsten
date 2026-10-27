# Hello world/Web server

use http

server = HTTP:Server.new(port: 8080)
server.get("/") -> (_req, res)
  res.write("Goodbye, World!")
server.start

## expect skip server example
