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
