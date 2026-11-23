# Integer overflow modes at the i64 boundary: `Math.promote / trap / wrap ->`
# blocks and `## i64` / `## u64` fixed-width locals — add, sub, mul, shift,
# negate, compound assignment. The compiled engine lowers these to guarded,
# native-wrapping or trapping machine ops (lowering/ops.w lower_binary_op);
# the interpreter mirrors them in maybe_wrap_int_arith. Only the trap block's
# non-overflowing behaviour is here — the abort itself ends the process and
# lives in int_overflow_trap_spec.w.
#
# Inside `Math.wrap` every op is computed into a local declared in the block
# and printed through that local: the compiled engine's inference types a
# boxed int op that sits inside a string interpolation differently (it
# promotes there), which is a compiled quirk this spec deliberately stays
# clear of. `## i64` operands wrap in either position. Compound assignment
# inside a Math.wrap block is the other known compiled divergence and lives
# in int_overflow_wrap_compound_spec.w.
#
# Cross-engine parity spec (scripts/parity.sh).

Math.promote ->
  p = 9223372036854775807
  p1 = p + 1
  << "promote.add [p1]"
  p2 = p * 2
  << "promote.mul [p2]"
  p3 = 0 - p - 2
  << "promote.sub [p3]"
  pt = 9223372036854775807 ## i64
  pt1 = pt + 1
  << "promote.typed.add [pt1]"
  pt2 = pt * 2
  << "promote.typed.mul [pt2]"

Math.wrap ->
  w = 9223372036854775807
  w1 = w + 1
  << "wrap.add [w1]"
  w2 = w * 2
  << "wrap.mul [w2]"
  w3 = 0 - w - 2
  << "wrap.sub [w3]"
  wn = 0 - 9223372036854775807 - 1
  << "wrap.min [wn]"
  wneg = -wn
  << "wrap.neg.min [wneg]"
  wm = wn * -1
  << "wrap.mul.neg [wm]"
  wd = wn - 1
  << "wrap.sub.min [wd]"
  w = w + 1
  << "wrap.reassign [w]"
  << "wrap.type [type(w)]"
  acc = 0
  i = 0
  while i < 3
    acc = acc + 9223372036854775807
    i += 1
  << "wrap.loop [acc]"
  ws = 1 << 63
  << "wrap.shl.promotes [ws]"
  wp = 2 ** 64
  << "wrap.pow.promotes [wp]"
  wb = (2 ** 70) + 1
  << "wrap.big.promotes [wb]"

Math.trap ->
  t1 = 140737488355327 - 1
  << "trap.inline.sub [t1]"
  t2 = 2 * 3
  << "trap.inline.mul [t2]"
  t3 = 2 ** 50
  t4 = t3 + 1
  << "trap.bigint.promotes [t4]"

t = 9223372036854775807 ## i64
<< "i64.add [t + 1]"
<< "i64.add.type [type(t + 1)]"
<< "i64.mul [t * 2]"
<< "i64.sub [5 - t - 10]"
tn = 0 - 9223372036854775807 - 1 ## i64
<< "i64.min [tn]"
<< "i64.neg.min [-tn]"
<< "i64.neg.minus [-tn - 1]"
<< "i64.sub.lit [tn - 1]"
<< "i64.lit.sub [0 - tn]"
s = 1 ## i64
<< "i64.shl.62 [s << 62]"
<< "i64.shl.63 [s << 63]"
<< "i64.shl.chain [(s << 63) << 1]"
k = 6 ## i64
<< "i64.mul.lit [k * 3074457345618258603]"
t += 1
<< "i64.compound.add [t]"
sh = 3 ## i64
sh <<= 62
<< "i64.compound.shl [sh]"
r = 9223372036854775807 ## i64
r = 9223372036854775807
r = r + 1
<< "i64.sticky [r]"

u = 0 ## u64
<< "u64.sub [u - 1]"
<< "u64.shr [(u - 1) >> 60]"
<< "u64.cmp [u - 1 > 0]"
um = 18446744073709551615 ## u64
um += 2
<< "u64.compound [um]"
<< "u64.mul [um * 18446744073709551615]"
