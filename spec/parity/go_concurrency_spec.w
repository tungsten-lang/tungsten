# `go -> body` goroutines against channels: unbuffered rendezvous between
# main and a goroutine (both directions, several handoffs), a worker loop,
# a goroutine spawning a goroutine, fan-in from a pool, captured locals,
# rescue inside a goroutine, a rendezvous from inside a method call chain,
# Mutex/Atomic across goroutines, a goroutine inside a method touching ivars,
# an early `return` from a body, and the end-of-main drain that lets a
# goroutine finish after the main body. (`go` under Math.wrap is in
# go_overflow_mode_spec.w and a goroutine parked inside `begin` in
# go_rescue_park_spec.w; `parallel with` is in
# parallel_with_side_effects_spec.w — a compiled divergence.)
#
# Both engines run goroutines on the runtime's cooperative scheduler: a
# goroutine gets the thread only while main is blocked in a channel op (or in
# the end-of-main drain) and keeps it until it blocks itself, so every
# interleaving below is deterministic and the print order is the transcript.
# The interpreter runs each body as a real runtime goroutine
# (interpreter/runtime.w spawn_goroutine); the compiled engine lowers it through
# lower_go — same w_goroutine_spawn, same scheduler.
#
# Cross-engine parity spec (scripts/parity.sh).

ch = Channel.new(0)
done = Channel.new(1)
go ->
  << "g: sending"
  ch.send(1)
  << "g: sent"
  ch.send(2)
  << "g: sent 2"
  done.send(true)
<< "m: receiving"
v = ch.receive
<< "m: got [v]"
v2 = ch.receive
<< "m: got [v2]"
done.receive
<< "m: done"

ping = Channel.new(0)
pong = Channel.new(0)
go ->
  i = 0
  while i < 3
    n = ping.receive
    << "worker got [n]"
    pong.send(n * 10)
    i += 1
  << "worker exit"
i = 1
while i <= 3
  ping.send(i)
  << "main got [pong.receive]"
  i += 1

results = Channel.new(4)
go ->
  << "outer start"
  go ->
    << "inner start"
    results.send("inner")
  results.send("outer")
a = results.receive
b = results.receive
<< "collected [a] [b]"

-> square(x)
  x * x
out = Channel.new(0)
[1, 2, 3, 4].each -> (k)
  go ->
    out.send(square(k))
sum = 0
j = 0
while j < 4
  sum += out.receive
  j += 1
<< "sum [sum]"

errs = Channel.new(0)
go ->
  begin
    raise "boom"
  rescue e
    errs.send("rescued [e]")
  errs.send("after rescue")
<< errs.receive
<< errs.receive

-> relay(src, dst)
  x = src.receive
  dst.send(x + 1)
c1 = Channel.new(0)
c2 = Channel.new(0)
go ->
  relay(c1, c2)
c1.send(41)
<< "relay [c2.receive]"

+ Counter
  -> new
    @n = 0
  -> bump
    @n += 1
  -> n
    @n

m = Mutex.new
c = Counter.new
at = Atomic.new(0)
fin = Channel.new(0)
k = 0
while k < 4
  go ->
    r = 0
    while r < 100
      m.synchronize ->
        c.bump
      at.increment
      r += 1
    fin.send(true)
  k += 1
k = 0
while k < 4
  fin.receive
  k += 1
<< "counter [c.n] atomic [at.load]"

+ Worker
  -> new(@name)
    @out = Channel.new(0)
  -> start
    go ->
      @out.send("hello from [@name]")
    self
  -> out
    @out
w = Worker.new("w1").start
<< w.out.receive

er = Channel.new(0)
go ->
  er.send("before return")
  return
  er.send("after return")
<< er.receive
<< "main after early-return goroutine"

late = Channel.new(1)
go ->
  late.receive
  << "late goroutine ran after main body"
late.send(true)
<< "main body end"
