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

# ChannelTrySendResult — nonblocking/select send outcome with three states.
+ ChannelTrySendResult
  SENT = 1
  UNAVAILABLE = 0
  CLOSED = -1

  -> new(@value, @status)

  -> value
    @value

  -> sent?
    @status == SENT

  -> unavailable?
    @status == UNAVAILABLE

  -> closed?
    @status == CLOSED

  -> ready?
    !unavailable?()

  -> to_a
    [@value, @status]

# An explicit select arm. Raw Channel entries remain receive arms for
# compatibility; these objects add send arms without making Array shape
# carry hidden semantics.
+ ChannelSelectArm
  ro :channel, :operation, :value

  -> new(@channel, @operation, @value = nil)

# ChannelSelection — the ready channel, result, and original input index.
+ ChannelSelection
  ro :channel, :result, :index, :operation

  -> new(@channel, @result, @index, @operation = :receive)

  -> value
    @result.value()

  -> received?
    @operation == :receive && @result.received?()

  -> sent?
    @operation == :send && @result.sent?()

  -> closed?
    @result.closed?()

+ Channel
  is Enumerable

  -> .unbounded
    ccall("w_chan_new_unbounded")

  -> .receive_case(channel)
    ChannelSelectArm.new(channel, :receive)

  -> .send_case(channel, value)
    ChannelSelectArm.new(channel, :send, value)

  # A received value, completed send, or closed channel is ready; nil means
  # the optional millisecond timeout expired. Raw Channels are receive arms.
  -> .select(arms, milliseconds = nil)
    if !arms.is_a?(Array) || arms.empty?()
      raise "Channel.select requires a non-empty Array of arms"
    if milliseconds != nil && (!milliseconds.is_a?(Integer) || milliseconds < 0)
      raise "Channel.select timeout must be a non-negative Integer in milliseconds"

    deadline = nil
    if milliseconds != nil
      deadline = clock_ms() + milliseconds
    offset = clock_ms() % arms.size

    while true
      i = 0
      while i < arms.size
        index = (offset + i) % arms.size
        arm = arms[index]
        operation = :receive
        channel = arm
        value = nil
        if arm.is_a?(ChannelSelectArm)
          operation = arm.operation()
          channel = arm.channel()
          value = arm.value()
        if ccall("w_sync_handle_kind_support", channel) != 3
          raise "Channel.select arms must contain Channels"
        result = nil
        if operation == :receive
          result = channel.try_receive()
        elsif operation == :send
          status = ccall("w_chan_try_send_result", channel, value)
          result = ChannelTrySendResult.new(value, status)
        else
          raise "Channel.select arm operation must be :receive or :send"
        if result.ready?()
          return ChannelSelection.new(channel, result, index, operation)
        i += 1

      if deadline != nil && clock_ms() >= deadline
        return nil
      ccall("__w_sleep", ~0.0001)
      offset = (offset + 1) % arms.size

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
