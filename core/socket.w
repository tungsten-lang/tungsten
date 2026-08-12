# Socket — nonblocking TCP sockets integrated with Tungsten's event loop.
#
# Reads return nil at EOF or when a configured read deadline expires. close is
# idempotent. ByteArray operations preserve embedded NUL bytes and avoid the
# String conversion/copy used by write.
+ Socket
  -> .listen(host, port, backlog = 128)
  -> .connect(host, port)

  -> accept
  -> read(size = 4096)
  -> read_exact(size)
  -> read_into(buffer, offset, size)

  -> write(data)
  -> write_bytes(bytes)
  -> write_slice(bytes, offset, size)

  -> set_timeout(milliseconds)
  -> shutdown(how = 2)
  -> alpn_protocol
  -> close
