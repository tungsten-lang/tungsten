# B6: one-way disjointness of the bigint source-op seam.
#
# `w_add`/`w_sub`/`w_mul` admit a pair into the migrated source bodies via
# `bigint_src_shape` / `bigint_mul_src_shape` (runtime.c): both heap
# BigInts, 2..4096 limbs (2..24 for `*`), excluding equal-length pairs
# whose RAW signs match (C keeps its *_equal_fast arms) and squaring.
# The source bodies (core/numeric/big_int.w) carry NO tag or zero checks
# of their own — every entry route proves heap-BigInt operands (the
# guarded direct call site, the w_add shape gate, the dispatcher's typed
# gate). They BAIL back to C on: a magnitude over the band (w_add/w_sub,
# re-gated), the equal-length same-raw-sign stratum and squaring (direct
# bigint entries, which bypass the gate entirely). The sets are NOT
# complements, so the property that keeps the seam sound is one-way
# disjointness:
#
#     bail_set ∩ admit_set = ∅
#
# Nothing the source hands back to the C entry may be re-admitted, or the
# pair loops `w_add → src → w_add` until the stack dies (presenting as a
# segfault indistinguishable from a bad pointer — the original reverted
# hand-optimization). This spec exercises a pair AT AND JUST PAST every
# boundary of both sets, through infix (seam-gated) and explicit-send
# (dispatcher-gated, no shape pre-check) entries. If either side is ever
# widened into the other, the overlapping pair recurses and this spec
# crashes or hangs instead of printing its PASS lines.
#
# A zero-magnitude heap BigInt cannot reach the bodies at all: every
# route proves a tagged operand and normalization demotes any i48-range
# result (zero included) to an inline int — the int/bigint mixed rows
# below pin C's promotion arms for inline values.
#
# Run both engines; a mid-program runtime error still exits 0, so gates
# must diff the full output:
#   bin/tungsten spec/numeric/bigint_seam_disjoint_spec.w
#   bin/tungsten -o /tmp/seam_spec spec/numeric/bigint_seam_disjoint_spec.w && /tmp/seam_spec

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# Operand shapes, keyed by limb count (limb = 64 bits; i48 ends at 2^47).
one_a = 1 << 50                    # 1 limb
one_b = (1 << 52) + 9              # 1 limb
two_a = 1 << 100                   # 2 limbs
two_b = (1 << 90) + 7              # 2 limbs (unequal magnitude, same count)
two_c = (1 << 100) + 3             # 2 limbs, same count as two_a
three_a = (1 << 140) + 5           # 3 limbs
sb_hi = 1 << (64 * 23 + 10)        # 24 limbs — inside the mul band
sb_over = 1 << (64 * 24 + 10)      # 25 limbs — just past the mul band
band_hi = 1 << (64 * 4095 + 10)    # 4096 limbs — inside the add band
band_over = 1 << (64 * 4096 + 10)  # 4097 limbs — just past the add band

neg_two_b = 0 - two_b
neg_two_c = 0 - two_c
neg_three = 0 - three_a

# -- Infix entries: w_add/w_sub/w_mul shape-test FIRST, then source. --

# Migrated arm (admitted): unequal-length multi-limb, both sign mixes.
check("add.uneq.pos", (two_a + three_a) - three_a, two_a)
check("add.uneq.neg", (two_a + neg_three) - neg_three, two_a)
check("add.uneq.pin", two_a + two_b, 1268888540267514781771602329607)
check("sub.uneq.pin", two_a - two_b, 1266412660188944021221804081145)
check("sub.uneq.round", (three_a - two_b) + two_b, three_a)

# Equal-length same-raw-sign (C's *_equal_fast, NOT admitted).
check("add.eq.same_sign", (two_a + two_c) - two_c, two_a)
check("sub.eq.same_sign", (two_a - two_c) + two_c, two_a)
check("add.eq.same_sign.neg", (neg_two_c + neg_two_b) - neg_two_b, neg_two_c)

# Equal-length differing raw signs (admitted — no C arm).
check("add.eq.mixed_sign", (two_a + neg_two_c) - neg_two_c, two_a)
check("sub.eq.mixed_sign", (two_a - neg_two_c) + neg_two_c, two_a)

# One-limb operands (below the band, NOT admitted — C's fused u64 arm).
check("add.one_one", (one_a + one_b) - one_b, one_a)
check("add.one_multi", (one_a + three_a) - three_a, one_a)
check("sub.multi_one", (three_a - one_b) + one_b, three_a)

# Band edge and just past it (4096 admitted, 4097 NOT).
check("add.band_edge", (band_hi + two_a) - two_a, band_hi)
check("add.band_over", (band_over + two_a) - two_a, band_over)
check("sub.band_over", (band_over - band_hi) + band_hi, band_over)

# Int/bigint mixed rows: never admitted (one side is an inline int);
# C's promotion arms must keep them.
check("add.int_big", (5 + two_a) - two_a, 5)
check("add.big_int", (two_a + 5) - 5, two_a)
check("sub.big_to_zero", two_a - two_a, 0)

# Multiply band: [2,24] limbs, unequal or mixed-sign, no squaring.
check("mul.band.pin", ((1 << 130) + 3) * ((1 << 70) + 11), 1606938044258990275556934516485683894918133251371942870515745)
check("mul.band.commute", two_a * three_a, three_a * two_a)
check("mul.band.hi", (sb_hi * two_a) / two_a, sb_hi)
check("mul.band.over", (sb_over * two_a) / two_a, sb_over)
check("mul.square", (two_a * two_a) / two_a, two_a)
check("mul.eq.same_sign", (two_a * two_c) / two_c, two_a)
check("mul.eq.mixed", (two_a * neg_two_c) / neg_two_c, two_a)
check("mul.one", (one_a * two_a) / one_a, two_a)

# -- Explicit sends: dispatcher entry, NO shape pre-check. The body's own
# bails must land in C WITHOUT being re-admitted (tags pass, so the only
# live bail here is the band check; the sub-band shapes simply run the
# general source arms and must be correct, not merely non-crashing). --
check("send.add.uneq", two_a.+(three_a), two_a + three_a)
check("send.add.one", one_a.+(one_b), one_a + one_b)
check("send.add.eq_same", two_a.+(two_c), two_a + two_c)
check("send.sub.uneq", three_a.-(two_b), three_a - two_b)
check("send.mul.band", two_a.*(three_a), two_a * three_a)
check("send.add.band_over", band_over.+(two_a), band_over + two_a)
