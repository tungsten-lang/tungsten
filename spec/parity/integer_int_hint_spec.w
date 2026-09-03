# Integers: `## int` locals promote on overflow on both engines; `## i64`
# locals that stay in range agree too.
#
# Cross-engine parity spec (scripts/parity.sh).

c = 140737488355327 ## int
<< "int.promote [c + c]"
<< "int.promote.type [type(c + c)]"
-> doubling(n)
  acc = 140737488355327 ## int
  i = 0 ## i64
  while i < n
    acc = acc + acc
    i = i + 1
  acc
<< "doubling [doubling(10)]"
a = 140737488355327 ## i64
<< "i64.mul2 [a * 2]"
<< "i64.mul2.type [type(a * 2)]"
-> sum_squares(n)
  s = 0 ## i64
  i = 1 ## i64
  while i <= n
    s = s + i * i
    i = i + 1
  s
<< "sum_squares [sum_squares(1000)]"
d = 3 ## i64
<< "i64.div [d / 2]"
<< "i64.neg [-d]"
<< "i64.shift [d << 40]"
