# blade/udp — UDP for QUIC and DNS, on core's UDPSocket (nonblocking, on Tungsten's event loop).

+ Udp
  # ip: [a, b, c, d]
  -> new(ip, port)
    @sock = UDPSocket.new.connect(ip_string(ip), port)
    @buf = ByteArray.new(65536)

  -> send(b)
    @sock.send(b)

  # One datagram as a ByteArray, or nil when none arrives within ms milliseconds.
  # When ms <= 0, perform a true non-blocking recv(2) into the reusable scratch buffer
  # instead of sleeping 1 ms in poll(2) + malloc(65536) per datagram burst!
  -> recv(ms)
    if ms <= 0
      begin
        fd = @sock.handle() ## i64
        ptr = ccall_nobox("w_array_data_ptr", @buf) ## i64
        n = ccall_nobox("recv", fd, ptr, 65536 ## i64, 0 ## i64) ## i64
        return nil if n < 0
        return bslice(@buf, 0, n)
      rescue e
        return nil
    @sock.set_timeout(ms)
    begin
      @sock.recv_bytes(65536)
    rescue e
      nil

  -> close
    @sock.close


# DNS lives in blade/dns (DnsCache over a long-lived DnsResolver).
