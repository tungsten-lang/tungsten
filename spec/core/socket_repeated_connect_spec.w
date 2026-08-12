# Runtime-special class methods must not cache their empty source facade body.
# Before this regression fix, the first Socket.connect at one compiled call
# site returned a Socket and the second returned nil.

use core/socket

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit(1)

-> connect_once(port)
  Socket.connect("127.0.0.1", port)

port = 39474
listener = Socket.listen("127.0.0.1", port)
server = Thread.new ->
  i = 0
  while i < 2
    connection = listener.accept()
    connection.close()
    i += 1

first = connect_once(port)
check("socket.repeated.first", first != nil)
first.close()

second = connect_once(port)
check("socket.repeated.second", second != nil)
second.close()

server.join()
listener.close()
<< "socket_repeated_connect_spec: all checks passed"
