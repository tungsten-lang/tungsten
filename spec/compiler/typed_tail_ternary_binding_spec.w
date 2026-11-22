# A local assigned only from a typed call and then read in a trailing ternary
# came back nil on the compiled engine ("expected int, got nil"): the local's
# binding was spilled only on the then-arm's path, so the else-arm read an
# uninitialized slot. Assignments inside an if/ternary condition had the same
# hole. Branches now spill live bindings before they split.

$failures = 0

-> check(label, got, want)
  if got != want
    << "FAIL [label]: got [got], want [want]"
    $failures = $failures + 1

-> rb(d, st, n) (u8[] i64[] i64) i64
  return 0 if n == 0
  p = st[0]
  st[0] = p + n
  (p * 7 + n) & ((1 << n) - 1)

-> rsb(d, st, n) (u8[] i64[] i64) i64
  v = rb(d, st, n)
  v >= (1 << (n - 1)) ? v - (1 << n) : v

-> triple(n) (i64) i64
  n * 3

-> cond_assign_ternary(n) (i64) i64
  (m = triple(n)) > 10 ? m - 10 : m + 100

-> cond_assign_if(n) (i64) i64
  if (m = triple(n)) > 10
    return m
  m + 1000

-> cond_assign_elsif(n) (i64) i64
  if n > 100
    return 0
  elsif (m = triple(n)) > 10
    return m
  m + 1000

check("tail ternary else arm", rsb(u8[4], i64[4], 5), 5)
st = i64[4]
st[0] = 2
check("tail ternary then arm", rsb(u8[4], st, 5), -13)
check("cond assign ternary then", cond_assign_ternary(5), 5)
check("cond assign ternary else", cond_assign_ternary(1), 103)
check("cond assign if taken", cond_assign_if(5), 15)
check("cond assign if fallthrough", cond_assign_if(1), 1003)
check("cond assign elsif taken", cond_assign_elsif(5), 15)
check("cond assign elsif fallthrough", cond_assign_elsif(1), 1003)

if $failures > 0
  exit(1)
<< "PASS typed tail ternary binding"
