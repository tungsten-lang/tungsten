# Integer overflow modes: compound assignment on a boxed local inside
# `Math.wrap ->`. The interpreter treats `w += 1` as `w = w + 1` and wraps to
# i64; the compiled engine's compound-assign lowering routes a boxed `:int`
# target through the generic promoting runtime add regardless of the lexical
# mode (only an explicit binary `w = w + 1` reaches lower_binary_op's :wrap
# arm). `## i64` targets agree on both engines (int_overflow_modes_spec.w).
#
# Cross-engine parity spec (scripts/parity.sh).

Math.wrap ->
  w = 9223372036854775807
  w += 1
  << "wrap.compound.add [w]"
  m = 0 - 9223372036854775807 - 1
  m -= 1
  << "wrap.compound.sub [m]"
  p = 9223372036854775807
  p *= 2
  << "wrap.compound.mul [p]"
