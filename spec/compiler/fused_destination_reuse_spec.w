# Automatic fused destination reuse is a compiler proof, not a source-level
# assertion. These cases pin both sides of the proof boundary: a unique local
# is consumed in place, while a bare alias forces ordinary fresh allocation.

-> auto_reuse_values(n) (i64) i64
  x = i64[n]
  i = 0 ## i64
  while i < n
    x[i] = i
    i += 1

  y = (x .* 3) .+ 7
  k = 0 ## i64
  while k < 3
    y = (x .* 3) .+ (k & 15)
    k += 1
  y[0] + y[n - 1]

-> auto_reuse_self_input(n) (i64) i64
  x = i64[n]
  i = 0 ## i64
  while i < n
    x[i] = i
    i += 1

  y = (x .* 1) .+ 0
  k = 0 ## i64
  while k < 3
    y = (y .* 2) .+ 1
    k += 1
  y[0] + y[n - 1]

-> alias_forces_fresh_output(n) (i64) i64
  x = i64[n]
  i = 0 ## i64
  while i < n
    x[i] = i
    i += 1

  y = (x .* 3) .+ 7
  alias_of_y = y
  y = (x .* 3) .+ 9
  alias_of_y[0] + alias_of_y[n - 1] + y[0] + y[n - 1]

n = 257
<< (auto_reuse_values(n) == 772 ? "PASS fuse.auto_destination_reuse" : "FAIL fuse.auto_destination_reuse")
<< (auto_reuse_self_input(n) == 2062 ? "PASS fuse.auto_destination_self_input" : "FAIL fuse.auto_destination_self_input")
<< (alias_forces_fresh_output(n) == 1568 ? "PASS fuse.alias_forces_fresh_output" : "FAIL fuse.alias_forces_fresh_output")
