# A goroutine parks inside a `begin` region (an unbuffered Channel#send
# with no receiver yet) while main raises and rescues in between, and a
# goroutine raises and rescues after main has parked. Exception frames,
# block-return frames and the cleanup stack are thread-locals that the
# scheduler now swaps per goroutine (runtime.c g_unwind_enter /
# g_unwind_leave); without the swap, main's raise longjmped into the parked
# goroutine's frame (SIGBUS).
#
# Cross-engine parity spec (scripts/parity.sh).

ch = Channel.new(0)
go ->
  begin
    ch.send(1)
    ch.send(2)
    << "g: sent both"
  rescue e
    << "g: rescued [e]"
begin
  v = ch.receive
  << "m: got [v]"
  raise "main boom"
rescue e
  << "m: rescued [e]"
<< "m: second [ch.receive]"

go ->
  begin
    ch.send(3)
    raise "g boom"
  rescue e
    << "g2: rescued [e]"
begin
  << "m: third [ch.receive]"
rescue e
  << "m: wrong rescue [e]"
<< "m: end"
