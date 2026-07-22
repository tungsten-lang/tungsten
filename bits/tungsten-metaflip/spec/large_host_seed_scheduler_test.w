use ../lib/metaflip/fleet/basins

failures = 0 ## i64

-> large_seed_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL large-host seed scheduler: " + label
    return 1
  0

failures += large_seed_expect("canonical exact-selection width", ffbi_exact_seed_selection_limit() == 12)
failures += large_seed_expect("empty rotation", ffbi_rotating_seed_index(0, 7) == 0 - 1)
failures += large_seed_expect("positive rotation", ffbi_rotating_seed_index(7, 9) == 2)
failures += large_seed_expect("negative rotation", ffbi_rotating_seed_index(7, 0 - 1) == 6)

uses = i64[5]
uses[0] = 2
uses[1] = 0
uses[2] = 0
uses[3] = 1
uses[4] = 3
failures += large_seed_expect("rotating least-used tie", ffbi_least_used_seed_index(uses, 5, 2) == 2)
failures += large_seed_expect("next least-used tie", ffbi_least_used_seed_index(uses, 5, 1) == 1)

# Simulate a wide fleet's cheap source scheduler. Across many extra islands,
# every bank member must receive the same number of attempts up to one.
balanced = i64[7]
ticket = 0 ## i64
while ticket < 101
  index = ffbi_least_used_seed_index(balanced, balanced.size(), ticket * 5 + 3) ## i64
  balanced[index] = balanced[index] + 1
  ticket += 1
minimum = balanced[0] ## i64
maximum = balanced[0] ## i64
i = 1 ## i64
while i < balanced.size()
  if balanced[i] < minimum
    minimum = balanced[i]
  if balanced[i] > maximum
    maximum = balanced[i]
  i += 1
failures += large_seed_expect("balanced long-run exposure", maximum - minimum <= 1)

if failures > 0
  exit(1)
<< "PASS large-host seed scheduler exact-width=12 exposure=" + minimum.to_s() + ".." + maximum.to_s()
