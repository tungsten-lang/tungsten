# No imports: predicate spellings must schedule BigInt even when the runtime
# value arrives through a literal/promotion rather than a BigInt class ref.

-> check(name, got, expected)
  if got != expected
    << "FAIL autoload [name]: got=[got] expected=[expected]"
    exit(1)

one = 281474976710656
odd = one + 1
negative = 0 - odd
multi = 18446744073709551616

check("one class", one.class_name, "BigInt")
check("one zero", one.zero?, false)
check("one even", one.even?, true)
check("odd odd", odd.odd?, true)
check("negative", negative.negative?, true)
check("negative positive", negative.positive?, false)
check("multi even", multi.even?, true)
check("multi positive extra", multi.positive?(1, 2, 3), true)
<< "autoload: ok (literal, arithmetic promotion, signed one-limb, and multi-limb BigInt predicates)"
