# A typed instance method still has the boxed method-table ABI. Its direct
# callers must agree, including calls with typed-array elements and memo fns.
-> check(name, actual, expected)
  raise "[name]: got [actual], expected [expected]" if actual != expected

+ TypedInstanceAbiProbe
  -> abs(x) (i64) i64
    x < 0 ? 0 - x : x
  -> combine(x, y) (i64 i64) i64
    x * 3 + y
  -> one() i64
    1
  -> zero() i64
    0
  -> negative() i64
    -1
  -> optional(x = -7) (i64) i64
    x
  -> half(x) (i64) f64
    x * 0.5
  fn triple(x) (i64) i64
    x * 3
  -> .static_abs(x) (i64) i64
    x < 0 ? 0 - x : x
  -> exercise
    xs = i64[3]; xs[0] = -1; xs[1] = 0; xs[2] = 140737488355329
    check("array negative", abs(xs[0]), 1)
    check("array zero", abs(xs[1]), 0)
    check("wide machine", abs(xs[2]), 140737488355329)
    check("self negative", self.abs(-17), 17)
    check("two arguments", combine(-4, 7), -5)
    check("self two arguments", self.combine(2, -7), -1)
    check("return one", one(), 1)
    check("return zero", zero(), 0)
    check("return negative", negative(), -1)
    check("default", optional(), -7)
    check("explicit optional", optional(-19), -19)
    check("mixed return", half(-8), -4.0)
    check("memo", triple(-5), -15)
    check("memo repeat", triple(-5), -15)
    check("self memo", self.triple(7), 21)

p = TypedInstanceAbiProbe.new
p.exercise
check("instance direct", p.abs(-13), 13)
box = {"object": p}
check("dynamic negative", box["object"].abs(-23), 23)
check("dynamic one", box["object"].one(), 1)
check("dynamic memo", box["object"].triple(-5), -15)
check("static raw ABI", TypedInstanceAbiProbe.static_abs(-29), 29)
<< "PASS typed instance ABI (20 checks)"
