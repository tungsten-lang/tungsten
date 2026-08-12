# Fused multiply-accumulate with MULTI-LIMB factors: `r += a * b` /
# `r -= a * b` on a liveness-proved accumulator routes through
# w_bigint_addmul_mut/submul_mut into the multi-limb leg
# (w_bigint_linear_multi_mut) — product in retained scratch, folded into
# r's buffer, no boxed product. Every row twins against the staged
# two-operator reference; signs, aliasing, overlay-negated operands,
# capacity refusal, zero crossings, and polymorphic fallbacks included.
#
# E4 proof discipline (mut_walk_stmts): each fused function seeds its
# accumulator from LITERAL leaves and never tail-returns the bare var
# (`r + 0` keeps the proof alive), so the fused entries actually engage —
# a parameter-seeded or bare-returned accumulator silently degrades to the
# fallback and tests nothing.

-> check(name, got, want)
  if got.to_s() == want.to_s()
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# Wide positive seed.
-> fused_add(a, b, iters)
  r = ((1 << 640) + 424242) ## big
  i = 0 ## i64
  while i < iters
    r += a * b
    i += 1
  r + 0

-> fused_sub(a, b, iters)
  r = ((1 << 640) + 424242) ## big
  i = 0 ## i64
  while i < iters
    r -= a * b
    i += 1
  r + 0

# Wide negative seed (header-negative receiver).
-> fused_add_negseed(a, b, iters)
  r = (0 - ((1 << 640) + 424242)) ## big
  i = 0 ## i64
  while i < iters
    r += a * b
    i += 1
  r + 0

-> fused_sub_negseed(a, b, iters)
  r = (0 - ((1 << 640) + 424242)) ## big
  i = 0 ## i64
  while i < iters
    r -= a * b
    i += 1
  r + 0

# Narrow seed: product much wider than the accumulator (growth leg /
# capacity-refusal fallback on the first pass, in-place after).
-> fused_add_tiny(a, b, iters)
  r = ((1 << 64) + 9) ## big
  i = 0 ## i64
  while i < iters
    r += a * b
    i += 1
  r + 0

# Small positive seed swinging negative (opposite-sign compare<0 leg).
-> fused_sub_small(a, b, iters)
  r = ((1 << 100) + 5) ## big
  i = 0 ## i64
  while i < iters
    r -= a * b
    i += 1
  r + 0

# Inline-int seed under the same proof: the runtime preamble bails and the
# fallback must stay exact.
-> fused_add_inline(a, b, iters)
  r = 5 ## big
  i = 0 ## i64
  while i < iters
    r += a * b
    i += 1
  r + 0

# Staged references (product materialized; the accumulator add sees a
# plain operand, so no linear-word fusion applies). Seeds mirror the fused
# functions literal-for-literal.
-> staged(seed_sel, a, b, iters, subtract)
  r = 0 ## big
  if seed_sel == 1
    r = ((1 << 640) + 424242) ## big
  elsif seed_sel == 2
    r = (0 - ((1 << 640) + 424242)) ## big
  elsif seed_sel == 3
    r = ((1 << 64) + 9) ## big
  elsif seed_sel == 4
    r = ((1 << 100) + 5) ## big
  elsif seed_sel == 5
    r = 5 ## big
  elsif seed_sel == 6
    r = (1 << 300) ## big
  i = 0 ## i64
  while i < iters
    t = a * b
    if subtract
      r = r - t
    else
      r = r + t
    i += 1
  r + 0

a5 = (1 << 300) + (1 << 130) + 111111111
b3 = (1 << 150) + 222222222
a5n = 0 - a5
b3n = 0 - b3

# Sign matrix, addition (wide seed).
check("addmul.pp", fused_add(a5, b3, 7), staged(1, a5, b3, 7, false))
check("addmul.pn", fused_add(a5, b3n, 7), staged(1, a5, b3n, 7, false))
check("addmul.np", fused_add(a5n, b3, 7), staged(1, a5n, b3, 7, false))
check("addmul.nn", fused_add(a5n, b3n, 7), staged(1, a5n, b3n, 7, false))
check("addmul.negseed.pp", fused_add_negseed(a5, b3, 7), staged(2, a5, b3, 7, false))
check("addmul.negseed.pn", fused_add_negseed(a5, b3n, 7), staged(2, a5, b3n, 7, false))

# Sign matrix, subtraction.
check("submul.pp", fused_sub(a5, b3, 7), staged(1, a5, b3, 7, true))
check("submul.pn", fused_sub(a5, b3n, 7), staged(1, a5, b3n, 7, true))
check("submul.np", fused_sub(a5n, b3, 7), staged(1, a5n, b3, 7, true))
check("submul.nn", fused_sub(a5n, b3n, 7), staged(1, a5n, b3n, 7, true))
check("submul.negseed", fused_sub_negseed(a5, b3, 7), staged(2, a5, b3, 7, true))

# Zero crossing and recovery.
check("submul.crossing", fused_sub_small(a5, b3, 5), staged(4, a5, b3, 5, true))

# Exact cancellation to zero (compare == 0 leg): 2^150 * 2^150 == 2^300.
p150 = 1 << 150
-> fused_sub_cancel(a, b, iters)
  r = (1 << 300) ## big
  i = 0 ## i64
  while i < iters
    r -= a * b
    i += 1
  r + 0

check("submul.cancel.zero", fused_sub_cancel(p150, p150, 1), 0)
check("submul.cancel.twin", fused_sub_cancel(p150, p150, 1), staged(6, p150, p150, 1, true))

# Growth / capacity-refusal fallback, then very wide products.
check("addmul.grow", fused_add_tiny(a5, b3, 4), staged(3, a5, b3, 4, false))
awide = (1 << 2500) + 777
check("addmul.wide.product", fused_add(awide, b3, 3), staged(1, awide, b3, 3, false))

# Inline accumulator start: preamble bails, fallback still exact.
check("addmul.inline.seed", fused_add_inline(a5, b3, 3), staged(5, a5, b3, 3, false))

# Receiver aliasing INSIDE the product: r += r * b and r += b * r read the
# very buffer being written; the scratch product is formed first (the rows
# variant must refuse these shapes).
-> alias_self_left(b, iters)
  r = ((1 << 640) + 424242) ## big
  i = 0 ## i64
  while i < iters
    r += r * b
    i += 1
  r + 0

-> alias_self_right(b, iters)
  r = ((1 << 640) + 424242) ## big
  i = 0 ## i64
  while i < iters
    r += b * r
    i += 1
  r + 0

-> alias_self_staged(b, iters)
  r = ((1 << 640) + 424242) ## big
  i = 0 ## i64
  while i < iters
    t = r * b
    r = r + t
    i += 1
  r + 0

check("addmul.alias.left", alias_self_left(b3, 5), alias_self_staged(b3, 5))
check("addmul.alias.right", alias_self_right(b3, 5), alias_self_staged(b3, 5))

# Overlay-negated self-reference: r -= (0 - r) * b == r += r * b. The
# negate marks the buffer shared, so the entry must refuse mutation and
# fall back — values stay exact either way.
-> alias_self_negated(b, iters)
  r = ((1 << 640) + 424242) ## big
  i = 0 ## i64
  while i < iters
    m = 0 - r ## big
    r -= m * b
    i += 1
  r + 0

check("addmul.alias.negated", alias_self_negated(b3, 5), alias_self_staged(b3, 5))

# Snapshot integrity: an alias of the accumulator taken before the fused
# statement must keep its value (the entry may only consume a dead buffer;
# the bare-var copy kills the liveness proof by design).
base = (1 << 400) + 12321 ## big
keep = base
sum = base ## big
sum += a5 * b3
check("addmul.snapshot.kept", keep, (1 << 400) + 12321)
check("addmul.snapshot.result", sum, keep + a5 * b3)

# Polymorphic fallback: a non-integer factor leaves the fused spelling on
# ordinary dispatch.
-> float_fused(f, iters)
  r = 10 ## big
  i = 0 ## i64
  while i < iters
    r += 3 * f
    i += 1
  r + 0

-> float_staged(f, iters)
  r = 10 ## big
  i = 0 ## i64
  while i < iters
    t = 3 * f
    r = r + t
    i += 1
  r + 0

check("addmul.float.fallback", float_fused(2.5, 4), float_staged(2.5, 4))

# One-limb words must keep their existing path exactly.
w1 = 987654321987
check("addmul.word.regression", fused_add(a5, w1, 7), staged(1, a5, w1, 7, false))
check("submul.word.regression", fused_sub(a5, w1, 7), staged(1, a5, w1, 7, true))
