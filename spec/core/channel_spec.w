-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

channel = Channel.new(3)
check("channel.send.return", channel.send("first") == nil)
channel.send("second")
channel.send("third")

check("channel.receive.fifo", channel.receive() == "first")
check("channel.recv.alias", channel.recv() == "second")
check("channel.receive.third", channel.receive() == "third")

channel.send(42)
check("channel.close.return", channel.close() == nil)
check("channel.close.idempotent", channel.close() == nil)
check("channel.close.drains", channel.receive() == 42)
check("channel.close.empty", channel.receive() == nil)

nil_channel = Channel.new(2)
nil_channel.send(nil)
nil_channel.close()
nil_result = nil_channel.receive_result()
check("channel.result.nil.received", nil_result.received?())
check("channel.result.nil.value", nil_result.value() == nil)
check("channel.result.to_a", nil_result.to_a() == [nil, true])
closed_result = nil_channel.receive_result()
check("channel.result.closed", closed_result.closed?())
check("channel.result.closed.value", closed_result.value() == nil)

each_channel = Channel.new(3)
each_channel.send("first")
each_channel.send(nil)
each_channel.send("third")
each_channel.close()
seen = []
returned = each_channel.each -> (value)
  seen.push(value)
check("channel.each.nil_payload", seen == ["first", nil, "third"])
check("channel.each.returns_self", returned == each_channel)

unbounded = Channel.unbounded()
i = 0
while i < 40
  unbounded.send(i)
  i += 1
unbounded.close()
i = 0
unbounded_received = true
unbounded_fifo = true
while i < 40
  result = unbounded.receive_result()
  unbounded_received = false if !result.received?()
  unbounded_fifo = false if result.value() != i
  i += 1
check("channel.unbounded.received", unbounded_received)
check("channel.unbounded.fifo", unbounded_fifo)
check("channel.unbounded.closed", unbounded.receive_result().closed?())

closed_send_failed = false
begin
  channel.send(9)
rescue error
  closed_send_failed = error.to_s.include?("send on closed channel")
check("channel.close.rejects_send", closed_send_failed)

zero_failed = false
begin
  Channel.new(0)
rescue error
  zero_failed = error.to_s.include?("capacity must be positive")
check("channel.zero_capacity", zero_failed)

negative_failed = false
begin
  Channel.new(-1)
rescue error
  negative_failed = error.to_s.include?("capacity must be positive")
check("channel.negative_capacity", negative_failed)

<< "channel_spec: all checks passed"
