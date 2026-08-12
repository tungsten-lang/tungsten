# Channel — a thread-safe FIFO for goroutine communication.
#
# Channel.new(0) creates an unbuffered rendezvous and a positive capacity
# creates a bounded queue;
# Channel.unbounded grows as needed. Closing is idempotent; queued values remain
# receivable after close, then receive/recv returns nil. Use receive_result when
# nil is a valid payload or closed-and-drained state must be distinguished.

+ ChannelReceiveResult
  -> new(@value, @received)

  -> value
    @value

  -> received?
    @received

  -> closed?
    !@received

  -> to_a
    [@value, @received]

+ Channel
  is Enumerable

  -> .unbounded
    ccall("w_chan_new_unbounded")

  -> send(value)
    ccall("w_chan_send", self, value)

  -> receive
    ccall("w_chan_recv", self)

  -> recv
    receive()

  -> receive_result
    raw = ccall("w_chan_recv_result", self)
    ChannelReceiveResult.new(raw[0], raw[1])

  -> each(&)
    while true
      result = receive_result()
      return self if result.closed?()
      &(result.value())

  -> close
    ccall("w_chan_close", self)
