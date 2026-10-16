# spec: compiled -- exercises the ownership pass's loop-carried integer releases
# Loop-carried integer releases (compiler/lib/ownership.w, runtime
# w_value_release_loop): a loop that replaces an integer variable with integer
# arithmetic of itself frees the previous iteration's BigInt.  Every shape the
# release must refuse, or must survive, is checked against an independently
# computed value: identity results that alias the old value, a borrowed initial
# value, copies and containers that keep old values alive, non-integer loop
# values, nested loops, continue, break and an early return.

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# Reference without a loop: x -> (x * x + c) % m applied n times, recursively.
-> step_ref(x, n, c, m)
  return x if n == 0
  step_ref((x * x + c) % m, n - 1, c, m)

-> modsq_loop(x0, n, m)
  x = x0
  i = 0
  while i < n
    x = (x * x) % m
    i += 1
  x

-> identity_loop(a, n, m)
  x = a
  i = 0
  while i < n
    x = x * 1
    x = x + 0
    x = x % m
    x = x / 1
    x = x << 0
    i += 1
  x

-> borrowed_init(a, n, m)
  x = a
  i = 0
  while i < n
    x = (x * x + 7) % m
    i += 1
  [a, x]

-> copies_kept(x0, n)
  x = x0
  kept = []
  i = 0
  while i < n
    y = x
    x = x * 3
    kept.push(y)
    i += 1
  kept

-> pushed_each(x0, n)
  x = x0
  seen = []
  i = 0
  while i < n
    seen.push(x)
    x = x * x
    i += 1
  seen

-> nested(x0, outer, inner, m)
  x = x0
  i = 0
  while i < outer
    j = 0
    while j < inner
      x = (x * x + 1) % m
      j += 1
    i += 1
  x

-> with_continue(x0, n, m)
  x = x0
  i = 0
  while i < n
    i += 1
    next if i % 3 == 0
    x = (x * x + 1) % m
  x

-> with_break(x0, n, m)
  x = x0
  i = 0
  while i < n
    x = (x * x + 1) % m
    break if i == n / 2
    i += 1
  x

-> early_return(x0, n, m)
  x = x0
  i = 0
  while i < n
    x = (x * x + 1) % m
    return x if i == 5
    i += 1
  x

-> float_loop(n)
  x = 1.0
  i = 0
  while i < n
    x = x * 1.5
    i += 1
  x

-> string_loop(n)
  s = "a" * 70
  i = 0
  while i < n
    s = s + "bc"
    i += 1
  s

m = ((1 ## int) << 4000) - 159
big = ((7 ## int) ** 1200) + 12345
check("modular squaring matches modpow", modsq_loop(big, 40, m) == big.modpow((2 ## int) ** 40, m))
check("identity results keep the value", identity_loop(big, 30, m * m) == big)
pair = borrowed_init(big, 25, m)
check("borrowed initial value survives the loop", pair[0] == big && pair[0] + 1 == big + 1)
check("borrowed loop result", pair[1] == step_ref(big % m, 25, 7, m) || pair[1] == step_ref(big, 25, 7, m))
kept = copies_kept(big, 12)
ok = true
k = 0
while k < 12
  ok = false if kept[k] != big * (3 ## int) ** k
  k += 1
check("copies taken inside the loop stay valid", ok)
seen = pushed_each((3 ## int) ** 300, 6)
ok = true
k = 0
while k < 6
  ok = false if seen[k] != (3 ## int) ** (300 * (2 ## int) ** k)
  k += 1
check("values stored in a container stay valid", ok)
check("nested loops", nested(big, 4, 5, m) == step_ref(big, 20, 1, m))
check("continue keeps the loop correct", with_continue(big, 30, m) == step_ref(big, 20, 1, m))
check("break keeps the loop correct", with_break(big, 30, m) == step_ref(big, 16, 1, m))
check("early return keeps the loop correct", early_return(big, 30, m) == step_ref(big, 6, 1, m))
check("float loop values are untouched", float_loop(10) > 57.6 && float_loop(10) < 57.7)
check("string loop values are untouched", string_loop(100).size() == 270)

# Memory: 3,000 squarings of a 100,000-bit value kept every iteration's
# product and remainder before (about 130 MB); now only a few live at a time.
mm = ((1 ## int) << 100_000) - 1
r = modsq_loop((3 ## int) ** 1000, 3000, mm)
rss_kib = OS.capture("ps -o rss= -p $PPID").strip().to_i()
check("3,000 squarings at 100,000 bits stay under 60 MB (rss_kib=[rss_kib])", rss_kib > 0 && rss_kib < 61_440)
check("and the result is still right", r % 1000003 == ((3 ## int) ** 1000).modpow((2 ## int) ** 3000, mm) % 1000003)
<< "loop_carried_release_spec: all checks passed"
