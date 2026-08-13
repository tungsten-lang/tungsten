# SockAddr WValue Tag 0xFFF6 spec.
# Tests inline IPv4 + 16-bit Port socket endpoint tagging and port extraction.

endpoint = ccall("w_sockaddr_w", 127, 0, 0, 1, 8080)

is_sock = ccall("w_is_sockaddr_w", endpoint)
port = ccall("w_sockaddr_port_w", endpoint)

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

expect("sockaddr.is_sockaddr", is_sock)
expect("sockaddr.port", port == 8080)
