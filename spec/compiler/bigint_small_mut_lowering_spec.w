# Consumed BigInt +/- literal lowering. These functions intentionally keep
# their accumulator local and non-escaping so the existing liveness proof may
# select the raw-magnitude small-mut ABI. The alias/parameter/index controls
# must remain on the ordinary immutable routes.

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> compound_add_one
  r = (1 << 256) + 17
  r += 1
  r == (1 << 256) + 18

-> compound_sub_one
  r = (1 << 256) + 17
  r -= 1
  r == (1 << 256) + 16

-> assignment_add_two
  r = (1 << 256) + 17
  r = r + 2
  r == (1 << 256) + 19

-> assignment_sub_two
  r = (1 << 256) + 17
  r = r - 2
  r == (1 << 256) + 15

-> increment_one
  r = (1 << 256) + 17
  r++
  r == (1 << 256) + 18

-> decrement_one
  r = (1 << 256) + 17
  r--
  r == (1 << 256) + 16

# 2^63 + (2^63 - 1) = 2^64 - 1. This exercises full carry growth; the runtime
# differential harness separately constructs exact-capacity buffers and proves
# that refused growth leaves them undirtied.
-> full_carry_growth
  r = (1 << 63) + ((1 << 63) - 1)
  r += 1
  r == (1 << 64)

-> negative_add_two
  r = 0 - ((1 << 256) + 17)
  r += 2
  r == 0 - ((1 << 256) + 15)

-> negative_sub_two
  r = 0 - ((1 << 256) + 17)
  r -= 2
  r == 0 - ((1 << 256) + 19)

# The receiver starts outside i48 and the result canonicalizes back inline.
-> demote_at_i48_edge
  r = 1 << 47
  r -= 1
  r == 140737488355327

# Preserve the numeric result at the runtime's asymmetric negative i48 edge.
# Representation parity itself is pinned by bigint_leaf_ab; calling type(r)
# here would correctly disqualify this function from the liveness proof.
-> preserve_negative_i48_edge_value
  r = 0 - ((1 << 47) + 1)
  r += 1
  r == (0 - (1 << 47))

# Keep a boxed-arithmetic seed whose value is one; the result must still
# canonicalize to inline zero if the runtime guard refuses the receiver.
-> canonical_zero
  r = ((1 << 64) - ((1 << 64) - 1)) ## big
  r -= 1
  r == 0

# Exercise the AArch64 eight-limb carry/borrow chunks at an exact multiple and
# across a scalar tail.  The first crossing reserves spare capacity; the next
# three crossings must reuse the unique receiver and preserve both signs for
# raw magnitudes one and two.
-> ripple_chunks_16
  positive = (1 << 1024) - 1
  r = positive + 0
  r += 1
  r -= 1
  r += 2
  r -= 2
  negative = 0 - positive
  s = negative + 0
  s -= 1
  s += 1
  s -= 2
  s += 2
  r == positive && s == negative

-> ripple_small_boundary
  positive = (1 << 64) - 1
  r = positive + 0
  r += 1
  r -= 1
  r += 2
  r -= 2
  negative = 0 - positive
  s = negative + 0
  s -= 1
  s += 1
  s -= 2
  s += 2
  r == positive && s == negative

-> ripple_chunks_64
  positive = (1 << 4096) - 1
  r = positive + 0
  r += 1
  r -= 1
  r += 2
  r -= 2
  negative = 0 - positive
  s = negative + 0
  s -= 1
  s += 1
  s -= 2
  s += 2
  r == positive && s == negative

-> ripple_chunks_65
  positive = (1 << 4160) - 1
  r = positive + 0
  r += 1
  r -= 1
  r += 2
  r -= 2
  negative = 0 - positive
  s = negative + 0
  s -= 1
  s += 1
  s -= 2
  s += 2
  r == positive && s == negative

-> alias_disqualifies_small
  r = (1 << 256) + 17
  snapshot = r
  r += 1
  snapshot == (1 << 256) + 17 && r == (1 << 256) + 18

-> parameter_compound(r)
  r += 1
  r

-> parameter_disqualifies_small
  source = (1 << 256) + 17
  snapshot = source
  result = parameter_compound(source)
  snapshot == (1 << 256) + 17 && source == snapshot && result == (1 << 256) + 18

-> indexed_disqualifies_small
  original = (1 << 256) + 17
  values = [original]
  snapshot = values[0]
  values[0] += 1
  snapshot == original && values[0] == original + 1

check("small_mut.compound_add_one", compound_add_one())
check("small_mut.compound_sub_one", compound_sub_one())
check("small_mut.assignment_add_two", assignment_add_two())
check("small_mut.assignment_sub_two", assignment_sub_two())
check("small_mut.increment_one", increment_one())
check("small_mut.decrement_one", decrement_one())
check("small_mut.full_carry_growth", full_carry_growth())
check("small_mut.negative_add_two", negative_add_two())
check("small_mut.negative_sub_two", negative_sub_two())
check("small_mut.demote_at_i48_edge", demote_at_i48_edge())
check("small_mut.preserve_negative_i48_edge_value", preserve_negative_i48_edge_value())
check("small_mut.canonical_zero", canonical_zero())
check("small_mut.ripple_small_boundary", ripple_small_boundary())
check("small_mut.ripple_chunks_16", ripple_chunks_16())
check("small_mut.ripple_chunks_64", ripple_chunks_64())
check("small_mut.ripple_chunks_65", ripple_chunks_65())
check("small_mut.alias_disqualifies_small", alias_disqualifies_small())
check("small_mut.parameter_disqualifies_small", parameter_disqualifies_small())
check("small_mut.indexed_disqualifies_small", indexed_disqualifies_small())

<< "bigint_small_mut_lowering_spec: all checks passed"
