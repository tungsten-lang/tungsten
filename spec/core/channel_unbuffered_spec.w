-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

single = Channel.new(0)
single_done = Channel.new(1)
go ->
  single.send(nil)
  single_done.send(true)

single_result = single.receive_result()
check("channel.unbuffered.nil.received", single_result.received?())
check("channel.unbuffered.nil.value", single_result.value() == nil)
check("channel.unbuffered.sender.resumed", single_done.receive())
single.close()

many = Channel.new(0)
many_done = Channel.new(8)
[1, 2, 3, 4, 5, 6, 7, 8].each -> (value)
  go ->
    many.send(value)
    many_done.send(value)

sum = 0
i = 0
while i < 8
  sum += many.receive()
  i += 1
check("channel.unbuffered.multisender.values", sum == 36)

done_sum = 0
i = 0
while i < 8
  done_sum += many_done.receive()
  i += 1
check("channel.unbuffered.multisender.resumed", done_sum == 36)
many.close()
many_done.close()

closed = Channel.new(0)
closed.close()
closed_send_failed = false
begin
  closed.send(1)
rescue error
  closed_send_failed = error.to_s.include?("send on closed channel")
check("channel.unbuffered.closed.send", closed_send_failed)

pending_send = Channel.new(0)
send_ready = Channel.new(1)
send_woke = Channel.new(1)
go ->
  send_ready.send(true)
  begin
    pending_send.send(99)
  rescue error
    send_woke.send(error.to_s.include?("send on closed channel"))
send_ready.receive()
pending_send.close()
check("channel.unbuffered.close.discards_pending", pending_send.receive_result().closed?())
check("channel.unbuffered.close.wakes_sender", send_woke.receive())

pending_receive = Channel.new(0)
receive_ready = Channel.new(1)
receive_woke = Channel.new(1)
go ->
  receive_ready.send(true)
  receive_woke.send(pending_receive.receive_result().closed?())
receive_ready.receive()
pending_receive.close()
check("channel.unbuffered.close.wakes_receiver", receive_woke.receive())

<< "channel_unbuffered_spec: all checks passed"
