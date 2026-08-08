# use math/globals — opt-in top-level aliases for Math.*. Exact values only
# (equality follows exactness), plus a hot-loop accumulation exercising the
# raw-libm path under the compiled engine.

use math/globals

<< "sin0 " + sin(0.0).to_s()
<< "cos0 " + cos(0.0).to_s()
<< "sqrt9 " + sqrt(9.0).to_s()
<< "cbrt27 " + cbrt(27.0).to_s()
<< "exp0 " + exp(0.0).to_s()
<< "log1 " + log(1.0).to_s()
<< "pow " + pow(2.0, 10.0).to_s()
<< "hypot " + hypot(3.0, 4.0).to_s()
<< "atan2 " + atan2(0.0, 1.0).to_s()
<< "floor " + floor(2.75).to_s()
<< "ceil " + ceil(2.25).to_s()
<< "round " + round(2.5).to_s()
<< "abs " + abs(-2.5).to_s()

# ~zero-vs-zero: asin(0)/atan(0) are exactly 0.0
<< "asin0 " + asin(0.0).to_s()
<< "atan0 " + atan(0.0).to_s()

# Accumulation through the alias in a typed loop (raw-f64 path compiled).
acc = 0.0 ## f64
i = 0 ## i64
while i < 100
  acc = acc + sin(i.to_f() * 0.01)
  i += 1
<< "loop " + (acc > 4.9 && acc < 5.0).to_s()
