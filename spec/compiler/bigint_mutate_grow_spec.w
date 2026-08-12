# Mutate-if-unique, stage 4 (E4 gap closure). Covers the growth arms of
# w_bigint_add_mut/w_bigint_sub_mut (|b| > |a| in place and
# allocate+release), the carry-past-capacity class crossing, the
# multi-limb-multiplier destination recycle (w_bigint_mul_mut_wide,
# including the self-square), the multi-limb-divisor div/mod arms, and
# the subtract rotation (w_bigint_sub_dest). Every check pins BOTH
# halves of the D5 contract on BOTH engines: qualifying shapes compute
# exactly the immutable values, and every adversarial alias shape is
# either statically marked or runtime-guarded — observable values NEVER
# change. Run compiled AND interpreted; outputs must byte-match.

-> check(name, got, want)
  if got.to_s() == want.to_s()
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# --- |b| > |a| in place: the post-reduction accumulator shape. The
#     receiver's class has room, so the wide addend lands in the dying
#     buffer with no allocation; the subtract leg restores the seed. ---
-> grow_yoyo(n)
  r = (1 << 63) + 29
  x = (1 << 300) + 7
  i = 0 ## i64
  while i < n
    r += x
    r -= x
    i += 1
  r == (1 << 63) + 29
check("grow.yoyo_inplace", grow_yoyo(500), "true")

# --- all four sign pairs with |b| > |a| (straight-line shapes are
#     admitted too: candidacy is body-wide, not loop-bound) ---
-> grow_pp
  r = (1 << 63) + 29
  r += (1 << 300) + 7
  r == (1 << 300) + 7 + (1 << 63) + 29
check("grow.sign_pp", grow_pp(), "true")

-> grow_pn
  r = (1 << 63) + 29
  r -= (1 << 300) + 7
  r == (1 << 63) + 29 - ((1 << 300) + 7)
check("grow.sign_pn", grow_pn(), "true")

-> grow_np
  r = 0 - (1 << 63) - 29
  r += (1 << 300) + 7
  r == (1 << 300) + 7 - (1 << 63) - 29
check("grow.sign_np", grow_np(), "true")

-> grow_nn
  r = 0 - (1 << 63) - 29
  r -= (1 << 300) + 7
  r == 0 - (1 << 300) - 7 - (1 << 63) - 29
check("grow.sign_nn", grow_nn(), "true")

# --- growth boundary: 2^(64k) - 1 gains a limb past its exact class ---
-> carry_over_class(k)
  r = (1 << (64 * k)) - 1
  j = 0 ## i64
  while j < 3
    r += 1
    r -= 1
    j += 1
  r == (1 << (64 * k)) - 1
check("grow.carry_class_8", carry_over_class(8), "true")
check("grow.carry_class_32", carry_over_class(32), "true")

# --- self-alias doubling: r += r crosses classes repeatedly ---
-> self_double(n)
  r = (1 << 63) + 5
  i = 0 ## i64
  while i < n
    r += r
    i += 1
  r == ((1 << 63) + 5) * (1 << n)
check("grow.self_double", self_double(200), "true")

-> self_drain
  r = (1 << 200) + 123
  r -= r
  r == 0
check("grow.self_drain", self_drain(), "true")

# --- adversarial: plain alias before a growing overwrite; the alias is
#     marked at the copy, so the wide add must not move it ---
-> grow_alias_survives
  r = (1 << 63) + 29
  y = r
  r += (1 << 300) + 7
  y == (1 << 63) + 29
check("adv.grow_plain_alias", grow_alias_survives(), "true")

# --- adversarial: negate alias (tag-flip shares the buffer); the mark
#     minted by the negation must keep every mutating arm off it ---
-> negate_alias_add
  r = (1 << 200) + 7
  y = 0 - r
  r += (1 << 300) + 1
  y == 0 - (1 << 200) - 7
check("adv.negate_alias_add", negate_alias_add(), "true")

-> negate_alias_loop(n)
  r = (1 << 200) + 7
  y = 0 - r
  i = 0 ## i64
  while i < n
    r = r + 1
    i = i + 1
  y == 0 - (1 << 200) - 7
check("adv.negate_alias_loop", negate_alias_loop(1000), "true")

-> negate_alias_mul
  r = (1 << 100) + 3
  y = 0 - r
  r *= (1 << 100) + 5
  y == 0 - (1 << 100) - 3
check("adv.negate_alias_mul", negate_alias_mul(), "true")

# --- adversarial: identity alias (x + 0 returns x) feeding a grower ---
-> identity_seed_grow
  x = (1 << 63) + 41
  r = x + 0
  r += (1 << 300) + 9
  x == (1 << 63) + 41
check("adv.identity_seed_grow", identity_seed_grow(), "true")

# --- adversarial: container-stored accumulator must never mutate ---
-> hash_snapshot_grow(n)
  r = (1 << 63) + 3
  h = {}
  h["snap"] = r
  i = 0 ## i64
  while i < n
    r += (1 << 300) + 1
    r %= (1 << 127) + 55555
    i += 1
  h["snap"] == (1 << 63) + 3
check("adv.hash_snapshot_grow", hash_snapshot_grow(200), "true")

# --- multi-limb multiplier chain vs an alias-disqualified reference ---
-> mul_wide(n)
  r = (1 << 80) + 17
  m = (1 << 100) + 12345
  i = 0 ## i64
  while i < n
    r *= m
    i += 1
  r % 1000000007

-> mul_wide_ref(n)
  r = (1 << 80) + 17
  snap = r
  m = (1 << 100) + 12345
  i = 0 ## i64
  while i < n
    r = r * m
    i += 1
  snap == (1 << 80) + 17 ? r % 1000000007 : 0
check("mul.wide_chain", mul_wide(40), mul_wide_ref(40))

-> mul_wide_negative(n)
  r = 0 - (1 << 80) - 17
  m = (1 << 100) + 12345
  i = 0 ## i64
  while i < n
    r *= m
    i += 1
  r % 1000000007

-> mul_wide_negative_ref(n)
  r = 0 - (1 << 80) - 17
  snap = r
  m = (1 << 100) + 12345
  i = 0 ## i64
  while i < n
    r = r * m
    i += 1
  snap == 0 - (1 << 80) - 17 ? r % 1000000007 : 0
check("mul.wide_negative", mul_wide_negative(31), mul_wide_negative_ref(31))

-> mul_wide_negword(n)
  r = (1 << 80) + 17
  m = 0 - (1 << 100) - 12345
  i = 0 ## i64
  while i < n
    r *= m
    i += 1
  r % 1000000007

-> mul_wide_negword_ref(n)
  r = (1 << 80) + 17
  snap = r
  m = 0 - (1 << 100) - 12345
  i = 0 ## i64
  while i < n
    r = r * m
    i += 1
  snap == (1 << 80) + 17 ? r % 1000000007 : 0
check("mul.wide_negword", mul_wide_negword(31), mul_wide_negword_ref(31))

# self-square through the wide arm (r *= r with a multi-limb receiver)
-> sqr_wide(n)
  r = (1 << 100) + 3
  i = 0 ## i64
  while i < n
    r *= r
    r %= (1 << 511) + 111111
    i += 1
  r % 1000000007

-> sqr_wide_ref(n)
  r = (1 << 100) + 3
  snap = r
  i = 0 ## i64
  while i < n
    r = r * r
    r = r % ((1 << 511) + 111111)
    i += 1
  snap == (1 << 100) + 3 ? r % 1000000007 : 0
check("mul.self_square_wide", sqr_wide(50), sqr_wide_ref(50))

# --- multi-limb divisor: quotient chain, remainder chain, both signs ---
-> div_wide(n)
  r = (1 << 4096) + 987654321
  d = (1 << 127) + 55555
  i = 0 ## i64
  while i < n
    r /= d
    i += 1
  r % 1000000007

-> div_wide_ref(n)
  r = (1 << 4096) + 987654321
  snap = r
  d = (1 << 127) + 55555
  i = 0 ## i64
  while i < n
    r = r / d
    i += 1
  snap == (1 << 4096) + 987654321 ? r % 1000000007 : 0
check("div.wide_chain", div_wide(30), div_wide_ref(30))

-> div_wide_negative(n)
  r = 0 - (1 << 4096) - 987654321
  d = (1 << 127) + 55555
  i = 0 ## i64
  while i < n
    r /= d
    i += 1
  r % 1000000007

-> div_wide_negative_ref(n)
  r = 0 - (1 << 4096) - 987654321
  snap = r
  d = (1 << 127) + 55555
  i = 0 ## i64
  while i < n
    r = r / d
    i += 1
  snap == 0 - (1 << 4096) - 987654321 ? r % 1000000007 : 0
check("div.wide_negative", div_wide_negative(30), div_wide_negative_ref(30))

-> mod_wide(n)
  r = (1 << 8191) + 123456789
  bump = (1 << 4159) + 987654321
  d = (1 << 127) + 987654321987654321
  i = 0 ## i64
  while i < n
    r += bump
    r %= d
    i += 1
  r % 1000000007

-> mod_wide_ref(n)
  r = (1 << 8191) + 123456789
  snap = r
  bump = (1 << 4159) + 987654321
  d = (1 << 127) + 987654321987654321
  i = 0 ## i64
  while i < n
    r = r + bump
    r = r % d
    i += 1
  snap == (1 << 8191) + 123456789 ? r % 1000000007 : 0
check("mod.wide_chain", mod_wide(300), mod_wide_ref(300))

-> mod_wide_negative
  r = 0 - (1 << 4096) - 998877665544332211
  d = (1 << 190) + 51
  r %= d
  r == 0 - ((1 << 4096) + 998877665544332211) % ((1 << 190) + 51)
check("mod.wide_negative", mod_wide_negative(), "true")

# |a| < |b|: the remainder IS the receiver; the quotient retires it
-> mod_wide_identity
  r = (1 << 100) + 3
  r %= (1 << 300) + 7
  r == (1 << 100) + 3
check("mod.wide_identity", mod_wide_identity(), "true")

-> div_wide_zero
  r = (1 << 100) + 3
  r /= (1 << 300) + 7
  r == 0
check("div.wide_zero", div_wide_zero(), "true")

# --- subtract rotation (E4 stage 4): descending Fibonacci computed into
#     the dying buffer; values must match a shape the rotation must NOT
#     transform (t read twice), across demotion and full descent ---
-> fib_down(m, n)
  a = 0 ## big
  b = 1 ## big
  j = 0 ## i64
  while j < m
    t = a + b
    a = b
    b = t
    j = j + 1
  i = 0 ## i64
  while i < n
    t = b - a
    b = a
    a = t
    i = i + 1
  (a + b) % 1000000007

-> fib_down_ref(m, n)
  a = 0 ## big
  b = 1 ## big
  j = 0 ## i64
  while j < m
    t = a + b
    u = t
    a = b
    b = u
    j = j + 1
  i = 0 ## i64
  while i < n
    t = b - a
    u = t
    b = a
    a = u
    i = i + 1
  (a + b) % 1000000007
check("rot.fibdown_1000", fib_down(1030, 1000), fib_down_ref(1030, 1000))
check("rot.fibdown_full_descent", fib_down(300, 299), fib_down_ref(300, 299))

# adversarial: pre-loop alias of the dying rotation var — the slot copy
# marks the buffer, so the in-place subtract must refuse and y survive
-> fibdown_alias
  a = (1 << 200) + 1 ## big
  b = (1 << 100) + 1 ## big
  y = a
  i = 0 ## i64
  while i < 3
    t = a - b
    a = b
    b = t
    i += 1
  y == (1 << 200) + 1
check("adv.fibdown_prealias", fibdown_alias(), "true")

# adversarial regression: the PLUS rotation had the same hole when the
# seed had SLACK capacity (5 limbs in an 8-limb class — no carry-limb
# refusal to hide behind); the loop-entry seed marks close it for both
-> rot_add_prealias_slack
  a = (1 << 257) - 1 ## big
  b = (1 << 100) + 1 ## big
  y = a
  i = 0 ## i64
  while i < 3
    t = a + b
    a = b
    b = t
    i += 1
  y == (1 << 257) - 1
check("adv.rot_add_prealias_slack", rot_add_prealias_slack(), "true")

# adversarial: pre-loop container escape of a rotation seed
-> rot_escape_hash
  a = (1 << 257) - 1 ## big
  b = (1 << 100) + 1 ## big
  h = {}
  h["snap"] = a
  i = 0 ## i64
  while i < 5
    t = a - b
    a = b
    b = t
    i += 1
  h["snap"] == (1 << 257) - 1
check("adv.rot_escape_hash", rot_escape_hash(), "true")

# adversarial: an extra read of the dying var inside the loop disqualifies
-> fibdown_watch(m, n)
  a = 0 ## big
  b = 1 ## big
  j = 0 ## i64
  while j < m
    t = a + b
    a = b
    b = t
    j = j + 1
  seen = 0 ## i64
  i = 0 ## i64
  while i < n
    t = b - a
    b = a
    a = t
    if b.odd?
      seen = seen + 1
    i = i + 1
  ((a + b) + seen) % 1000000007

-> fibdown_watch_ref(m, n)
  a = 0 ## big
  b = 1 ## big
  j = 0 ## i64
  while j < m
    t = a + b
    a = b
    b = t
    j = j + 1
  seen = 0 ## i64
  i = 0 ## i64
  while i < n
    t = b - a
    u = t
    b = a
    a = u
    if b.odd?
      seen = seen + 1
    i = i + 1
  ((a + b) + seen) % 1000000007
check("rot.fibdown_extra_read", fibdown_watch(800, 700), fibdown_watch_ref(800, 700))

<< "bigint_mutate_grow_spec: all checks passed"
