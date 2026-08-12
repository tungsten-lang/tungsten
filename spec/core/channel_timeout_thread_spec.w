-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

unbuffered = Channel.new(0)
check("channel.unbuffered.try_send.no_receiver", !unbuffered.try_send(1))

received = Channel.new(1)
receiver = Thread.new -> received.send(unbuffered.receive())
deadline = clock() + ~0.25
sent = false
while !sent && clock() < deadline
  sent = unbuffered.try_send(9)
receiver.join()
check("channel.unbuffered.try_send.waiting_receiver", sent && received.receive() == 9)

# Once try_send reports success, a concurrent close must not discard that
# committed rendezvous before the already-waiting receiver consumes it.
committed_ok = true
iteration = 0
while iteration < 40
  committed = Channel.new(0)
  committed_result = Channel.new(1)
  committed_receiver = Thread.new -> committed_result.send(committed.receive_result())
  committed_deadline = clock() + ~0.25
  committed_sent = false
  while !committed_sent && clock() < committed_deadline
    committed_sent = committed.try_send(iteration)
  committed.close()
  result = committed_result.receive()
  committed_receiver.join()
  if !committed_sent || !result.received?() || result.value() != iteration
    committed_ok = false
  iteration += 1
check("channel.unbuffered.try_send.close_commit", committed_ok)

cancel_channel = Channel.new(0)
cancel_receiver = Thread.new -> cancel_channel.receive()
sleep(~0.01)
cancel_receiver.kill()
cancel_receiver.join()
check("channel.unbuffered.cancel_clears_readiness", !cancel_channel.try_send(5))
cancel_channel.close()

timed_receive_channel = Channel.new(0)
sender = Thread.new ->
  sleep(~0.01)
  timed_receive_channel.send(11)
timed_receive = timed_receive_channel.receive_result(100)
sender.join()
check("channel.receive.timeout.success", timed_receive.received?() && timed_receive.value() == 11)

timed_send_channel = Channel.new(0)
timed_send_value = Channel.new(1)
delayed_receiver = Thread.new ->
  sleep(~0.01)
  timed_send_value.send(timed_send_channel.receive())
check("channel.send.timeout.success", timed_send_channel.send(13, 100))
delayed_receiver.join()
check("channel.send.timeout.value", timed_send_value.receive() == 13)

ghost_channel = Channel.new(0)
check("channel.send.timeout.expires", !ghost_channel.send(17, 3))
check("channel.send.timeout.no_ghost", ghost_channel.try_receive().unavailable?())
ghost_channel.close()

closing = Channel.new(0)
closer = Thread.new ->
  sleep(~0.01)
  closing.close()
closed_result = closing.receive_result(100)
closer.join()
check("channel.receive.close_beats_timeout", closed_result.closed?())

select_left = Channel.new(1)
select_right = Channel.new(1)
select_sender = Thread.new ->
  sleep(~0.01)
  select_right.send(23)
selected = Channel.select([select_left, select_right], 100)
select_sender.join()
check("channel.select.delayed", selected != nil && selected.index() == 1 && selected.value() == 23)

<< "channel_timeout_thread_spec: all checks passed"
