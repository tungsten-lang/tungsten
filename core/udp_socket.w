# UDPSocket — nonblocking UDP datagram sockets integrated with Tungsten's
# event loop, the datagram counterpart of Socket.
#
#   server = UDPSocket.new()
#   server.bind("127.0.0.1", 0)            # port 0: the kernel picks one
#   client = UDPSocket.new().connect("127.0.0.1", server.local_port)
#   client.send(« 00 ff »)
#   data, host, port = server.recv_from()
#   server.send_to("pong", host, port)
#   client.set_timeout(250)
#   reply = client.recv()                  # "pong", or nil after 250 ms
#
# A socket is IPv4 unless made with UDPSocket.new(:ipv6); host names resolve
# in that family, as Socket.connect resolves them. connect fixes the peer for
# send and recv. Each recv answers exactly one datagram, truncated to `max`
# bytes; it parks the calling fiber on the event loop until one arrives, and
# answers nil once the set_timeout deadline passes (no timeout: it waits).
# recv and recv_from answer a String, as Socket#read does, with every byte
# preserved, NULs included; recv_bytes answers a ByteArray (u8[]). send and
# send_to take a String or a ByteArray and answer the bytes sent. close is
# idempotent.
#
# The descriptor lives in the runtime (w_udp_*); @handle is its handle, nil
# once closed.
+ UDPSocket
  -> new(family = :ipv4)
    case family
      :ipv4 => @handle = ccall("w_udp_open", 4)
      :ipv6 => @handle = ccall("w_udp_open", 6)
      => raise ArgumentError.new("UDPSocket.new: family must be :ipv4 or :ipv6, got " + family.to_s)
    @family = family
    @timeout_ms = 0

  ro :family

  -> handle
    raise IOError.new("closed UDP socket") if @handle == nil
    @handle

  # Bind the local address; host nil or "" is every interface.
  -> bind(host, port)
    ccall("w_udp_bind", self.handle(), host, port)
    self

  # Fix the peer: send goes to it, and only its datagrams are received.
  -> connect(host, port)
    ccall("w_udp_connect", self.handle(), host, port)
    self

  -> send(data)
    ccall("w_udp_send", self.handle(), data)

  -> send_to(data, host, port)
    ccall("w_udp_send_to", self.handle(), data, host, port)

  -> recv(max = 65536)
    ccall("w_udp_recv", self.handle(), max, @timeout_ms, false)

  -> recv_bytes(max = 65536)
    ccall("w_udp_recv", self.handle(), max, @timeout_ms, true)

  # [data, host, port] of the next datagram, or nil on timeout.
  -> recv_from(max = 65536)
    ccall("w_udp_recv_from", self.handle(), max, @timeout_ms, false)

  # Receive deadline in milliseconds for each recv; 0 or less waits forever.
  -> set_timeout(milliseconds)
    @timeout_ms = milliseconds > 0 ? milliseconds : 0
    self

  -> local_port
    ccall("w_udp_local_port", self.handle())

  -> close
    if @handle != nil
      handle = @handle
      @handle = nil
      ccall("w_udp_close", handle)
    nil

  -> closed?
    @handle == nil
