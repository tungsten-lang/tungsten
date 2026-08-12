# Channel — a bounded, thread-safe FIFO for goroutine communication.
#
# Capacity must be positive. Closing is idempotent; buffered values remain
# receivable after close, then receive/recv returns nil. Because nil is also a
# valid payload, iteration and nonblocking receive wait for a future result API
# that distinguishes a value from closed-and-drained state.
+ Channel
  -> send(value)
    ccall("w_chan_send", self, value)

  -> receive
    ccall("w_chan_recv", self)

  -> recv
    receive()

  -> close
    ccall("w_chan_close", self)
