# The tree walker recycles method frames and temporary argument vectors.
# Captured method arguments and returned splats must survive later calls.
-> remember_arg(value)
  -> (unused) value

-> collect_args(*items)
  items

-> digits(a, b, c, d)
  1000*a + 100*b + 10*c + d

first = remember_arg(11)
second = remember_arg(22)
old = collect_args(1, 2)
newer = collect_args(3, 4)
if first.call(nil) != 11 || second.call(nil) != 22 || old != [1, 2] || newer != [3, 4]
  raise "later call overwrote a captured argument"

partial = digits(1, _, 3, _)
if partial.call(2, 4) != 1234
  raise "partial application lost argument order"
closures = [11, 22].map -> (value)
  -> (unused) value
if closures[0].call(nil) != 11 || closures[1].call(nil) != 22
  raise "later block invocation overwrote a captured parameter"
<< "method frame lifetime passed"
