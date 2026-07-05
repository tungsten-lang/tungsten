require "socket"

server = TCPServer.new("127.0.0.1", 8083)
response = "HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\nHello World\n"

while conn = server.accept
  conn.readpartial(4096) rescue nil
  conn.write(response)
  conn.close
end
