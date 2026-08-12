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

send_target = Channel.new(1)
receive_target = Channel.new(1)
mixed = Channel.select([
  Channel.receive_case(receive_target),
  Channel.send_case(send_target, 42)
], 0)
check("channel.select.send.operation", mixed != nil && mixed.operation() == :send)
check("channel.select.send.ready", mixed.sent?() && mixed.value() == 42)
check("channel.select.send.delivered", send_target.receive() == 42)

receive_target.send(9)
send_target.send(1)
mixed_receive = Channel.select([
  Channel.send_case(send_target, 2),
  Channel.receive_case(receive_target)
], 0)
check("channel.select.receive.operation", mixed_receive.operation() == :receive)
check("channel.select.receive.value", mixed_receive.received?() && mixed_receive.value() == 9)
check("channel.select.full.send.no_ghost", send_target.receive() == 1 && send_target.try_receive().unavailable?())

closed_send_target = Channel.new(1)
closed_send_target.close()
closed_send = Channel.select([Channel.send_case(closed_send_target, 3)], 0)
check("channel.select.closed_send.ready", closed_send.closed?() && !closed_send.sent?())

bad_arm = false
begin
  Channel.select([ChannelSelectArm.new(send_target, :other)], 0)
rescue error
  bad_arm = error.to_s.include?("operation")
check("channel.select.arm_validation", bad_arm)

<< "channel_timeout_spec: all checks passed"
