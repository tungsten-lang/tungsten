# Regression (2026-10-21): a compound assignment to a reassigned typed
# parameter must survive the next `if`/`while`. The prologue copies such a
# parameter into a slot but kept its entry binding, and materialize_bindings
# (run before every branch) stored that stale binding back over the slot. So
# `-> dec(size) (i64) i64 / size -= 1 / if ... / size` returned the old size,
# and a heap pop written that way never shrank the heap. A plain
# `size = size - 1` cleared the binding and was unaffected.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> dec_then_if(size) (i64) i64
  size -= 1
  if size > 100
    << "unreachable"
  size

-> dec_then_while(n) (i64) i64
  n -= 2
  k = 0
  while k < 3
    k += 1
  n + k

-> twice(x) (i64) i64
  x *= 2
  if x > 0
    x += 1
  x

-> heap_pop(keys, size) (i64[] i64) i64
  size -= 1
  if size > 0
    last = keys[size]
    i = 0
    while true
      c = 2 * i + 1
      if c >= size
        break
      if c + 1 < size && keys[c + 1] > keys[c]
        c += 1
      if keys[c] <= last
        break
      keys[i] = keys[c]
      i = c
    keys[i] = last
  size

-> untyped_dec(size)
  size -= 1
  if size > 100
    << "unreachable"
  size

-> defaulted(size = 10)
  size -= 1
  if size > 100
    << "unreachable"
  size

+ Counter
  -> .dec(size) (i64) i64
    size -= 1
    if size > 100
      << "unreachable"
    size

check("dec then if", dec_then_if(10), 9)
check("dec then while", dec_then_while(10), 11)
check("multiply then if", twice(5), 11)
keys = i64[5]
i = 0
while i < 5
  keys[i] = 50 - 10 * i
  i += 1
check("heap pop shrinks", heap_pop(keys, 5), 4)
check("heap pop keeps the max order", keys[0], 40)
check("untyped param", untyped_dec(10), 9)
check("defaulted param", defaulted(), 9)
check("class method param", Counter.dec(10), 9)
