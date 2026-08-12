# Compiled loopback integration for core/http.w. The server uses a native OS
# thread so it can accept and answer while HTTP.get blocks on the main thread.

use core/http

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit(1)

port = 39472
listener = Socket.listen("127.0.0.1", port)
request_seen = Channel.new(1)
server = Thread.new ->
  connection = listener.accept()
  request = connection.read(4096)
  request_seen.send(request)
  connection.write(
    "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nX-Loopback: yes\r\n\r\npong")
  connection.close()

response = HTTP.get("http://127.0.0.1:[port]/ping?x=1", {"Accept": "text/plain"})
request = request_seen.receive()
server.join()

check("http.socket.request_line", request.starts_with?("GET /ping?x=1 HTTP/1.1\r\n"))
check("http.socket.host", request.include?("Host: 127.0.0.1:[port]\r\n"))
check("http.socket.custom_header", request.include?("Accept: text/plain\r\n"))
check("http.socket.connection_close", request.include?("Connection: close\r\n\r\n"))
check("http.socket.status", response.status == 200)
check("http.socket.header", response.header("x-loopback") == "yes")
check("http.socket.body", response.body == "pong")

listener.close()

# Request bodies use Socket#write_bytes, preserving embedded NUL bytes that
# Socket#write's C-string-compatible convenience path cannot represent.
binary_port = 39473
binary_listener = Socket.listen("127.0.0.1", binary_port)
binary_request_seen = Channel.new(1)
binary_server = Thread.new ->
  connection = binary_listener.accept()
  request = ""
  loop
    chunk = connection.read(4096)
    break if chunk == nil
    request += chunk
    header_end = request.index("\r\n\r\n")
    break if header_end != nil && request.size >= header_end + 7
  binary_request_seen.send(request)
  connection.write("HTTP/1.1 204 No Content\r\n\r\n")
  connection.close()

binary_response = HTTP.post("http://127.0.0.1:[binary_port]/bytes", "a\0b")
binary_request = binary_request_seen.receive()
binary_server.join()
check("http.socket.binary_length", binary_request.include?("Content-Length: 3\r\n"))
check("http.socket.binary_body_size", binary_request.slice(binary_request.size - 3, 3).size == 3)
check("http.socket.binary_body_nul", binary_request.slice(binary_request.size - 2, 1) == "\0")
check("http.socket.no_content", binary_response.status == 204 && binary_response.body.empty?)

binary_listener.close()
<< "http_socket_spec: all checks passed"
