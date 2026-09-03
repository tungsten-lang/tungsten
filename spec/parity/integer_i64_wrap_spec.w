## parity xfail `## i64` locals wrap on overflow compiled but promote to bignum interpreted (b + 1 at i64 max, d << 62)
# Integers: `## i64` annotated locals at the i64 boundary.
#
# Cross-engine parity spec (scripts/parity.sh).

b = 9223372036854775807 ## i64
<< "i64.max [b]"
<< "i64.wrap [b + 1]"
-> doubling64(n)
  acc = 140737488355327 ## i64
  i = 0 ## i64
  while i < n
    acc = acc + acc
    i = i + 1
  acc
<< "doubling64 [doubling64(10)]"
<< "doubling64.wrap [doubling64(20)]"
d = 3 ## i64
<< "i64.shift [d << 62]"
<< "i64.shift.wrap [d << 63]"
