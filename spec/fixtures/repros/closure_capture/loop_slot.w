# Repro: goroutines spawned once per iterator-block invocation must each
# capture THAT iteration's value, not share one slot holding the last
# value. Each block invocation is a fresh frame, so the captured block
# param gets a fresh heap cell per iteration. (A `while`-loop local is a
# single binding by design — closures created in the loop share it, like
# Ruby/JS locals — so this repro uses the per-iteration block-param shape.)
# Compiled-only: Channel / goroutines are compiled-runtime builtins.

ch = Channel.new(8)
[10, 20, 30, 40].each -> (v)
  go ->
    ch.send(v)
sum = 0
got = []
i = 0
while i < 4
  x = ch.recv()
  sum += x
  got.push(x)
  i += 1
<< "sum: " + sum.to_s()
<< "distinct: " + got.include?(10).to_s() + got.include?(20).to_s() + got.include?(30).to_s() + got.include?(40).to_s()

# Same shape through the range.each with-loop path (a separate inline
# lowering from the array iterator): the gate must fall back to the real
# closure path here too.
ch2 = Channel.new(8)
(0..3).each -> (i)
  go ->
    ch2.send(i * 10)
rsum = 0
j = 0
while j < 4
  rsum += ch2.recv()
  j += 1
<< "range sum: " + rsum.to_s()
