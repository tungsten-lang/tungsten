# spec: compiled interpreter
# No imports: predicate spellings must schedule BigInt even when the runtime
# value arrives through a literal/promotion rather than a BigInt class ref.

# Surplus arguments are an error on both engines: E_LOWER_ARITY at compile
# time where the receiver's class is statically known, otherwise a rescuable
# ArgumentError at the call (the interpreter when it binds parameters, the
# compiled engine on the inline-cache miss path). This spec runs in both
# lanes.
-> surplus_rejected?(f)
  begin
    f.call
    false
  rescue surplus_error
    true

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
check("multi positive extra rejected", surplus_rejected?(->() multi.positive?(1, 2, 3)), true)
<< "autoload: ok (literal, arithmetic promotion, signed one-limb, and multi-limb BigInt predicates)"
