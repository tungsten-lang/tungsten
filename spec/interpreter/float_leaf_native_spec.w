# Compiled/tree-walker parity for source-only Float identity/classification
# leaves.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

check("positive abs", (~3.5).abs, ~3.5)
check("negative abs", (~-3.5).abs, ~3.5)
check("subnormal abs", (~-0.00000000000000000001).abs,
      ~0.00000000000000000001)
check("abs surplus arguments", (~-7.25).abs(1, 2), ~7.25)

positive_infinity = Math.exp(~10000.0)
negative_infinity = ~0.0 - positive_infinity
not_a_number = Math.sqrt(~-1.0)

identity_values = [~0.0, ~-0.0, ~3.5, ~-3.5, positive_infinity,
                   negative_infinity, not_a_number]
i = 0
while i < identity_values.size
  value = identity_values[i]
  # Ordinary equality is intentionally false for NaN. Exact WValue bits below
  # are the identity contract for that representation.
  if !value.nan?
    check("to_f value identity", value.to_f, value)
  check("to_f bit identity", wvalue_bits(value.to_f), wvalue_bits(value))
  check("to_f surplus identity", wvalue_bits(value.to_f(1, 2, 3)),
        wvalue_bits(value))
  i += 1

check("finite nan", (~1.0).nan?, false)
check("NaN nan", not_a_number.nan?, true)
check("infinity nan", positive_infinity.nan?, false)
check("finite infinite", (~1.0).infinite?, false)
check("positive infinite", positive_infinity.infinite?, true)
check("negative infinite", negative_infinity.infinite?, true)
check("NaN infinite", not_a_number.infinite?, false)
check("NaN abs remains NaN", not_a_number.abs.nan?, true)
check("negative infinity abs", negative_infinity.abs.infinite?, true)

<< "PASS Float source leaf parity"
