# A shortened typed call must canonicalize array types just like full arity.
-> check(actual, expected)
  raise "got [actual], expected [expected]" if actual != expected

-> array_default(xs, factor = 2) (i64[] i64) i64
  xs[0] * factor
-> narrow_default(xs, factor = 3) (i8[] i64) i64
  xs[0] * factor
-> dependent_default(xs, offset = xs[0]) (i64[] i64) i64
  xs[0] + offset
-> generic_default(xs, offset = 4) (Array i64) i64
  xs[0] + offset

wide = i64[1]; wide[0] = -7
narrow = i8[1]; narrow[0] = -3
check(array_default(wide), -14)
check(array_default(wide, 3), -21)
check(narrow_default(narrow), -9)
check(narrow_default(narrow, 4), -12)
check(dependent_default(wide), -14)
check(dependent_default(wide, 2), -5)
check(generic_default([9]), 13)
check(generic_default([9], 6), 15)
<< "PASS typed array default arguments (8 checks)"
