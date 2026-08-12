# Compile-time power-of-two DIVISOR context. The specialized compiled path
# (w_bigint_div_pow2: truncated magnitude shift) must match ordinary
# truncated `/` for boundary exponents, both signs, aliases, and the
# overlay-negated spelling. Materialized-divisor twins keep the arithmetic
# reference on the generic w_div path.

-> check(name, got, want)
  if got.to_s() == want.to_s()
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

p = ((1 << 520) + (1 << 257) + (1 << 129) + 123456789) ## big
n = 0 - p ## big

m1 = 1 << 1
m46 = 1 << 46
m47 = 1 << 47
m63 = 1 << 63
m64 = 1 << 64
m65 = 1 << 65
m127 = 1 << 127
m128 = 1 << 128
m129 = 1 << 129
m519 = 1 << 519
m521 = 1 << 521

check("divp2.positive.1", p / (1 << 1), p / m1)
check("divp2.positive.46", p / (1 << 46), p / m46)
check("divp2.positive.47", p / (1 << 47), p / m47)
check("divp2.positive.63", p / (1 << 63), p / m63)
check("divp2.positive.64", p / (1 << 64), p / m64)
check("divp2.positive.65", p / (1 << 65), p / m65)
check("divp2.positive.127", p / (1 << 127), p / m127)
check("divp2.positive.128", p / (1 << 128), p / m128)
check("divp2.positive.129", p / (1 << 129), p / m129)
check("divp2.positive.519", p / (1 << 519), p / m519)
check("divp2.positive.zeroed", p / (1 << 521), 0)
check("divp2.positive.one", p / (1 << 0), p)

# Truncation semantics: a negative dividend rounds toward ZERO, never
# toward -infinity — the twin generic `/` is the oracle.
check("divp2.negative.1", n / (1 << 1), n / m1)
check("divp2.negative.46", n / (1 << 46), n / m46)
check("divp2.negative.47", n / (1 << 47), n / m47)
check("divp2.negative.63", n / (1 << 63), n / m63)
check("divp2.negative.64", n / (1 << 64), n / m64)
check("divp2.negative.65", n / (1 << 65), n / m65)
check("divp2.negative.128", n / (1 << 128), n / m128)
check("divp2.negative.519", n / (1 << 519), n / m519)
check("divp2.negative.zeroed", n / (1 << 521), 0)
check("divp2.negative.one", n / (1 << 0), n)

# Explicit truncation pins beyond the twin: trunc ≠ floor exactly when a
# negative dividend has shifted-out low bits.
tvf = 0 - ((1 << 64) + 1) ## big
check("divp2.trunc.vs.floor", tvf / (1 << 1), 0 - (1 << 63))
tsn = 0 - 7 ## big
check("divp2.trunc.small.neg", tsn / (1 << 1), -3)

# The `/` and `%` pow2 entries must stay consistent: a == (a/m)*m + a%m.
recon_p = (p / (1 << 65)) * m65 + (p % (1 << 65))
check("divp2.reconstruct.pos", recon_p, p)
recon_n = (n / (1 << 65)) * m65 + (n % (1 << 65))
check("divp2.reconstruct.neg", recon_n, n)

# Truncated pairing: remainder carries the dividend's sign.
check("divp2.rem.sign.neg", n % (1 << 65) <= 0, true)

# Inline-int dividends under a :bigint static fact take the entry's inline
# leg (k >= 47 discards everything below 2^47).
small = 12345 ## big
check("divp2.inline.small", small / (1 << 3), 1543)
check("divp2.inline.wide", small / (1 << 47), 0)
smalln = 0 - 12345 ## big
check("divp2.inline.neg", smalln / (1 << 3), -1543)

# Overlay-negated alias as the DIVIDEND: y shares p's buffer with the
# tag-sign bit flipped; the entry must compose the sign (raw header read
# would divide a positive).
y = (0 - p) ## big
check("divp2.overlay.dividend", y / (1 << 65), n / m65)
check("divp2.overlay.source.intact", p / (1 << 65), p / m65)

# Compound consume: the liveness-proved form may reuse the receiver
# (literal seed + non-bare tail keep the E4 proof alive).
-> compound_div_positive
  r = ((1 << 520) + (1 << 257) + 987654321) ## big
  r /= 1 << 129
  r + 0

-> assignment_div_negative
  r = (0 - ((1 << 520) + (1 << 257) + 987654321)) ## big
  r = r / (1 << 129)
  r + 0

cp_ref = ((1 << 520) + (1 << 257) + 987654321) / m129
an_ref = (0 - ((1 << 520) + (1 << 257) + 987654321)) / m129
check("divp2.compound.consume", compound_div_positive(), cp_ref)
check("divp2.assignment.consume", assignment_div_negative(), an_ref)

# Aliased receiver: compound `/=` must not mutate the snapshot's value.
aliased = ((1 << 300) + 77) ## big
snapshot = aliased
aliased /= 1 << 128
check("divp2.compound.alias.old", snapshot, (1 << 300) + 77)
check("divp2.compound.alias.result", aliased, ((1 << 300) + 77) / m128)

# Identity (k = 0) preserves aliases on both spellings.
identity = ((1 << 200) + 99) ## big
identity_snapshot = identity
identity /= 1 << 0
check("divp2.identity.alias.old", identity_snapshot, (1 << 200) + 99)
check("divp2.identity.result", identity, (1 << 200) + 99)

# Full-discard consume leg.
zeroed = ((1 << 200) + 99) ## big
zeroed /= 1 << 256
check("divp2.compound.zeroed", zeroed, 0)

# A dynamic exponent must not fold — same value through the generic path.
kv = 65
check("divp2.dynamic.k", p / (1 << kv), p / (1 << 65))

# Chained shrink loop: `/=` inside a loop (consume steady-state) agrees
# with the twin loop dividing by the materialized constant.
-> shrink_fused(seed)
  r = seed ## big
  steps = 0 ## i64
  while r != 0
    r /= 1 << 64
    steps += 1
  steps

-> shrink_generic(seed)
  r = seed ## big
  d = 1 << 64
  steps = 0 ## i64
  while r != 0
    r = r / d
    steps += 1
  steps

seed = (1 << 521) + (1 << 300) + 424242
check("divp2.loop.steps", shrink_fused(seed), shrink_generic(seed))
seedn = 0 - seed
check("divp2.loop.steps.neg", shrink_fused(seedn), shrink_generic(seedn))
