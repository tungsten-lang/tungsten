require "socket"

server = TCPServer.new("0.0.0.0", 8080)
server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)

RESPONSE = "HTTP/1.1 200 OK\r\nContent-Length: 12\r\nConnection: keep-alive\r\n\r\nHello World\n"

loop do
  client = server.accept
  Thread.new(client) do |sock|
    begin
      buf = +""
      while (data = sock.readpartial(65536))
        buf << data
        # Count complete requests (each ends with \r\n\r\n)
        while (idx = buf.index("\r\n\r\n"))
          buf = buf[(idx + 4)..]
          sock.write(RESPONSE)
        end
      end
    rescue EOFError, Errno::ECONNRESET, Errno::EPIPE
    ensure
      sock.close
    end
  end
end
