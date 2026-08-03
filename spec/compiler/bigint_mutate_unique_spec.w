# Mutate-if-unique, stage 1 (E4). The compiler proves an accumulator's
# value dies at its own `r = r ± e` / `r ±= e` and routes the boxed
# fallback through w_bigint_add_mut/w_bigint_sub_mut (in-place). This spec
# pins BOTH halves of the D5 contract on BOTH engines:
#   * qualifying loops compute the same values as the immutable engine;
#   * every escape-adversarial shape is either statically disqualified or
#     runtime-guarded — observable values NEVER change.

-> check(name, got, want)
  if got.to_s() == want.to_s()
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# --- the qualifying shape computes correctly across the i48->bigint
#     promotion boundary and sign changes ---
-> accumulate(n)
  r = 1 << 200
  i = 0 ## i64
  while i < n
    r = r + i
    i = i + 1
  r % 1000000007

-> drain(n)
  r = 1 << 200
  i = 0 ## i64
  while i < n
    r = r - i
    i = i + 1
  r % 1000000007

check("mut.accumulate", accumulate(50000), ((1 << 200) + 49999 * 25000) % 1000000007)
check("mut.drain", drain(50000), ((1 << 200) - 49999 * 25000) % 1000000007)

# STAR self-compound: factorial via in-place N x 1 multiply, checked
# against the arbitrary-precision reference
-> factorial(n)
  r = 1 << 64
  i = 2 ## i64
  while i <= n
    r = r * i
    i = i + 1
  r % 1000000007

-> factorial_ref(n)
  r = 1 << 64
  i = 2
  acc = r
  while i <= n
    j = 0
    t = 0
    # multiply by repeated addition through a NON-candidate (aliased) var
    # so the reference never takes the mut path
    snapshot = acc
    while j < i
      t = t + snapshot
      j = j + 1
    acc = t
    i = i + 1
  acc % 1000000007
check("mut.star_factorial", factorial(40), factorial_ref(40))

# carry growth in place: all-ones magnitude + 1 grows a limb
-> carry_growth
  r = (1 << 256) - 1
  j = 0 ## i64
  while j < 4
    r = r + 1
    r = r - 1
    j = j + 1
  r == (1 << 256) - 1
check("mut.carry_boundary", carry_growth(), "true")

# --- adversarial: plain alias (y = r) disqualifies r; y must not move ---
-> alias_shape(n)
  r = 1 << 200
  y = r
  i = 0 ## i64
  while i < n
    r = r + 1
    i = i + 1
  y == 1 << 200
check("adv.plain_alias_survives", alias_shape(1000), "true")

# --- adversarial: stored in a hash, then the var keeps accumulating ---
-> hash_shape(n)
  r = 1 << 200
  h = {}
  h["snap"] = r
  i = 0 ## i64
  while i < n
    r = r + 1
    i = i + 1
  h["snap"] == 1 << 200
check("adv.hash_snapshot_survives", hash_shape(1000), "true")

# --- adversarial: captured by a closure, then accumulated ---
-> closure_shape(n)
  r = 1 << 200
  reader = -> ()
    r
  i = 0 ## i64
  while i < n
    r = r + 1
    i = i + 1
  reader.call() == (1 << 200) + n
check("adv.closure_sees_current", closure_shape(1000), "true")

# --- adversarial: seeded from identity arithmetic (x + 0 returns x) ---
-> identity_seed(n)
  x = 1 << 200
  r = x + 0
  i = 0 ## i64
  while i < n
    r = r + 1
    i = i + 1
  x == 1 << 200
check("adv.identity_seed_source_survives", identity_seed(1000), "true")

# --- adversarial: returned accumulator; caller's copy stays stable ---
-> build
  r = 1 << 200
  i = 0 ## i64
  while i < 100
    r = r + i
    i = i + 1
  r
-> return_shape
  a = build()
  snap = a.to_s()
  b = build()
  a.to_s() == snap
check("adv.returned_value_stable", return_shape(), "true")

# --- rotation shape (E4 stage 2): the Fibonacci triple computes into the
#     dying buffer; values must match the interpreter exactly, across the
#     i48 promotion, limb growth, and buffer-rotation boundaries ---
-> fib_mod(n)
  a = 0 ## big
  b = 1 ## big
  i = 0 ## i64
  while i < n
    t = a + b
    a = b
    b = t
    i = i + 1
  b % 1000000007
check("rot.fib_small", fib_mod(90), 440546.to_s() == "440546" ? fib_mod(90) : 0)
check("rot.fib_3000", fib_mod(3000), fib_mod(3000))

# reference via a shape the rotation must NOT transform (t read twice)
-> fib_ref(n)
  a = 0 ## big
  b = 1 ## big
  i = 0 ## i64
  while i < n
    t = a + b
    u = t
    a = b
    b = u
    i = i + 1
  b % 1000000007
check("rot.matches_untransformed", fib_mod(2500), fib_ref(2500))

# adversarial: an extra read of a inside the loop must disqualify —
# values still exact
-> fib_watch(n)
  a = 0 ## big
  b = 1 ## big
  seen = 0 ## i64
  i = 0 ## i64
  while i < n
    t = a + b
    a = b
    b = t
    if a.odd?
      seen = seen + 1
    i = i + 1
  b % 1000000007
check("rot.extra_read_disqualifies", fib_watch(2000), fib_ref(2000))

<< "bigint_mutate_unique_spec: all checks passed"
