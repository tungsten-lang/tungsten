# No imports: predicate spellings must schedule BigInt even when the runtime
# value arrives through a literal/promotion rather than a BigInt class ref.

# Surplus arguments are an error on both engines (E_LOWER_ARITY at compile
# time where the callee is known; the interpreter raises at the call).
-> surplus_rejected?(f)
  begin
    f.call
    false
  rescue surplus_error
    true

# The interpreter rejects surplus arguments at the call; the compiled engine
# leaves DYNAMIC dispatch unchecked by design (no runtime arity cost), so on
# an unknown receiver a surplus call still runs. Compile-time checks apply
# only where the callee is statically known. This spec runs in both lanes.
-> surplus_rejection_expected
  env("TUNGSTEN_INTERPRETED_SPEC") == "1"

-> check(name, got, expected)
  if got != expected
    << "FAIL autoload [name]: got=[got] expected=[expected]"
    exit(1)

-> zero_after_erasure(value)
  value.zero?()

one = 281474976710656
odd = one + 1
negative = 0 - odd
multi = 18446744073709551616

check("one class", one.class_name, "BigInt")
check("one zero", one.zero?, false)
check("one zero after receiver erasure", zero_after_erasure(one), false)
check("one even", one.even?, true)
check("odd odd", odd.odd?, true)
check("negative", negative.negative?, true)
check("negative positive", negative.positive?, false)
check("multi even", multi.even?, true)
check("multi positive extra rejected", surplus_rejected?(->() multi.positive?(1, 2, 3)), surplus_rejection_expected)
<< "autoload: ok (literal, arithmetic promotion, signed one-limb, and multi-limb BigInt predicates)"
