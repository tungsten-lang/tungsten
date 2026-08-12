# Channel — a thread-safe FIFO for goroutine communication.
#
# Channel.new(0) creates an unbuffered rendezvous and a positive capacity
# creates a bounded queue; Channel.unbounded grows as needed. Closing is
# idempotent; queued values remain receivable after close, then receive/recv
# returns nil. Result objects distinguish a received nil, temporary
# unavailability/timeout, and closed-and-drained state.

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

# ChannelTryReceiveResult — nonblocking/timed receive outcome with three states.
+ ChannelTryReceiveResult
  RECEIVED = 1
  UNAVAILABLE = 0
  CLOSED = -1

  -> new(@value, @status)

  -> value
    @value

  -> received?
    @status == RECEIVED

  -> unavailable?
    @status == UNAVAILABLE

  -> timed_out?
    unavailable?()

  -> closed?
    @status == CLOSED

  -> ready?
    !unavailable?()

  -> to_a
    [@value, @status]

# ChannelSelection — the ready channel, result, and original input index.
+ ChannelSelection
  ro :channel, :result, :index

  -> new(@channel, @result, @index)

  -> value
    @result.value()

  -> received?
    @result.received?()

  -> closed?
    @result.closed?()

+ Channel
  is Enumerable

  -> .unbounded
    ccall("w_chan_new_unbounded")

  # Receive-select over channels. A received value or a closed channel is
  # ready; nil means the optional millisecond timeout expired. Mixed send and
  # receive arms remain a future extension.
  -> .select(channels, milliseconds = nil)
    if !channels.is_a?(Array) || channels.empty?()
      raise "Channel.select requires a non-empty Array of channels"
    if milliseconds != nil && (!milliseconds.is_a?(Integer) || milliseconds < 0)
      raise "Channel.select timeout must be a non-negative Integer in milliseconds"

    deadline = nil
    if milliseconds != nil
      deadline = clock_ms() + milliseconds
    offset = clock_ms() % channels.size

    while true
      i = 0
      while i < channels.size
        index = (offset + i) % channels.size
        channel = channels[index]
        result = channel.try_receive()
        if result.ready?()
          return ChannelSelection.new(channel, result, index)
        i += 1

      if deadline != nil && clock_ms() >= deadline
        return nil
      ccall("__w_sleep", ~0.0001)
      offset = (offset + 1) % channels.size

  -> send(value)
    ccall("w_chan_send", self, value)

  # Wait up to `milliseconds` for space/a rendezvous. True means sent; false
  # means timeout. Sending on a closed channel always raises.
  -> send(value, milliseconds)
    ccall("w_chan_send_timeout", self, value, milliseconds)

  -> try_send(value)
    ccall("w_chan_try_send", self, value)

  -> receive
    ccall("w_chan_recv", self)

  -> recv
    receive()

  -> receive_result
    raw = ccall("w_chan_recv_result", self)
    ChannelReceiveResult.new(raw[0], raw[1])

  # Timed receive returns a three-state result: received, timed out, or closed.
  -> receive_result(milliseconds)
    raw = ccall("w_chan_recv_timeout_result", self, milliseconds)
    ChannelTryReceiveResult.new(raw[0], raw[1])

  -> try_receive
    raw = ccall("w_chan_try_recv_result", self)
    ChannelTryReceiveResult.new(raw[0], raw[1])

  -> try_receive_result
    try_receive()

  -> each(&)
    while true
      result = receive_result()
      return self if result.closed?()
      &(result.value())

  -> close
    ccall("w_chan_close", self)
