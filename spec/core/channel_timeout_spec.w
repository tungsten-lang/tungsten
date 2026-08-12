-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

buffered = Channel.new(1)
empty = buffered.try_receive()
check("channel.try_receive.unavailable", empty.unavailable?() && !empty.ready?())
check("channel.try_send.ready", buffered.try_send(nil))
check("channel.try_send.full", !buffered.try_send(2))
nil_result = buffered.try_receive_result()
check("channel.try_receive.nil", nil_result.received?() && nil_result.value() == nil)

receive_start = clock()
timed_out = buffered.receive_result(5)
check("channel.receive.timeout.state", timed_out.timed_out?())
check("channel.receive.timeout.waited", clock() - receive_start >= ~0.003)

buffered.send(1)
send_start = clock()
check("channel.send.timeout.state", !buffered.send(2, 5))
check("channel.send.timeout.waited", clock() - send_start >= ~0.003)
check("channel.send.timeout.no_ghost", buffered.receive() == 1 && buffered.try_receive().unavailable?())

buffered.close()
closed = buffered.try_receive()
check("channel.try_receive.closed", closed.closed?() && closed.ready?())

closed_send = false
begin
  buffered.try_send(3)
rescue error
  closed_send = error.to_s.include?("send on closed channel")
check("channel.try_send.closed", closed_send)

left = Channel.new(1)
right = Channel.new(1)
right.send(7)
selected = Channel.select([left, right], 0)
check("channel.select.ready.index", selected != nil && selected.index() == 1)
check("channel.select.ready.value", selected.received?() && selected.value() == 7)
check("channel.select.timeout", Channel.select([left, right], 2) == nil)
left.close()
selected_closed = Channel.select([left, right], 0)
check("channel.select.closed", selected_closed.channel() == left && selected_closed.closed?())

bad_select = false
begin
  Channel.select([])
rescue error
  bad_select = error.to_s.include?("non-empty Array")
check("channel.select.validation", bad_select)

<< "channel_timeout_spec: all checks passed"
