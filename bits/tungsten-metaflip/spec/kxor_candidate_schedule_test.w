# Regression for the bounded Cartesian tail used by square k-XOR.
#
# Production pools retain only a short prefix.  The schedule must therefore be
# a complete permutation when allowed to finish and must not spend that prefix
# holding the first two axes fixed while merely exhausting the third.

use ../lib/metaflip/kernels/kxor
use core/system

-> ffxcs_expect(label, condition) (String bool) i64
  if condition == false
    << "FAIL square kxor candidate schedule: " + label
    exit(1)
  0

na = 4 ## i64
nb = 5 ## i64
nc = 6 ## i64
plane = nb * nc ## i64
total = na * plane ## i64
seen = i64[total]
ordinal = 0 ## i64
while ordinal < total
  index = ffx_cartesian_index(total, 13, ordinal) ## i64
  z = ffxcs_expect("index in range", index >= 0 && index < total) ## i64
  z = ffxcs_expect("no duplicate", seen[index] == 0)
  seen[index] = 1
  ordinal += 1
index = 0
while index < total
  z = ffxcs_expect("complete permutation", seen[index] == 1)
  index += 1

seen_a = i64[na]
seen_b = i64[nb]
seen_c = i64[nc]
prefix = 8 ## i64
ordinal = 0
while ordinal < prefix
  index = ffx_cartesian_index(total, 13, ordinal)
  a = index / plane ## i64
  rem = index - a * plane ## i64
  b = rem / nc ## i64
  c = rem - b * nc ## i64
  seen_a[a] = 1
  seen_b[b] = 1
  seen_c[c] = 1
  ordinal += 1
distinct_a = 0 ## i64
distinct_b = 0 ## i64
distinct_c = 0 ## i64
index = 0
while index < na
  distinct_a += seen_a[index]
  index += 1
index = 0
while index < nb
  distinct_b += seen_b[index]
  index += 1
index = 0
while index < nc
  distinct_c += seen_c[index]
  index += 1
z = ffxcs_expect("short prefix spans U", distinct_a == na)
z = ffxcs_expect("short prefix spans V", distinct_b >= 2)
z = ffxcs_expect("short prefix spans W", distinct_c == nc)
z = ffxcs_expect("subset rotation changes prefix", ffx_cartesian_index(total, 14, 0) != ffx_cartesian_index(total, 13, 0))

<< "PASS square kxor candidate schedule permutation=" + total.to_s() + " prefix_axes=" + distinct_a.to_s() + "/" + distinct_b.to_s() + "/" + distinct_c.to_s()
