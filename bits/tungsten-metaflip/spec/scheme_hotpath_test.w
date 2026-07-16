# Invariants for the O(1) pair-flip transaction and incremental density
# accumulator shared by square and rectangular CPU workers.

use ../lib/metaflip/rect

failures = 0 ## i64

-> hot_expect(label, condition) (String bool) i64
  if condition == 0
    << "FAIL " + label
    return 1
  0

-> hot_density_consistent(st) (i64[]) bool
  actual = ffw_view_bits(st, st[44], st[45], st[46], st[50], st[6]) ## i64
  expected = st[36] + st[64] ## i64
  if actual == expected
    return true
  false

-> hot_pressure_reference(st, u, v, w) (i64[] i64 i64 i64) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < st[6]
    slot = st[st[50] + i] ## i64
    same = 0 ## i64
    if st[st[44] + slot] == u
      same += 1
    if st[st[45] + slot] == v
      same += 1
    if st[st[46] + slot] == w
      same += 1
    if same == 2
      count += 1
    i += 1
  count

-> hot_pressure_suite(st) (i64[]) bool
  if st[6] < 2
    return false
  slot0 = st[st[50]] ## i64
  slot1 = st[st[50] + 1] ## i64
  u0 = st[st[44] + slot0] ## i64
  v0 = st[st[45] + slot0] ## i64
  w0 = st[st[46] + slot0] ## i64
  # Mix two terms so absent and zero-factor queries are covered as well as a
  # live term. Pressure is defined for either kind of proposed endpoint.
  u1 = u0 ^ st[st[44] + slot1] ## i64
  v1 = st[st[45] + slot1] ## i64
  w1 = w0 ^ st[st[46] + slot1] ## i64
  expected0 = hot_pressure_reference(st,u0,v0,w0) ## i64
  expected1 = hot_pressure_reference(st,u1,v1,w1) ## i64
  data = ccall_nobox("w_array_data_ptr",st) ## i64
  ok = 1 ## i64
  if ffw_pressure(st,u0,v0,w0) != expected0
    ok = 0
  if ffw_pressure_raw(data,1,u0,v0,w0) != expected0 || ffw_pressure_batch_raw(data,1,u0,v0,w0,u1,v1,w1,2) != expected0 + expected1
    ok = 0
  if ffw_pressure_raw(data,2,u0,v0,w0) != expected0 || ffw_pressure_batch_raw(data,2,u0,v0,w0,u1,v1,w1,2) != expected0 + expected1
    ok = 0
  if ffw_pressure_raw(data,3,u0,v0,w0) != expected0 || ffw_pressure_batch_raw(data,3,u0,v0,w0,u1,v1,w1,2) != expected0 + expected1
    ok = 0
  if ffw_pressure_raw(data,5,u0,v0,w0) != expected0 || ffw_pressure_batch_raw(data,5,u0,v0,w0,u1,v1,w1,2) != expected0 + expected1
    ok = 0
  if ffw_pressure_raw(data,6,u0,v0,w0) != expected0 || ffw_pressure_batch_raw(data,6,u0,v0,w0,u1,v1,w1,2) != expected0 + expected1
    ok = 0
  if ffw_pressure_raw(data,7,u0,v0,w0) != expected0 || ffw_pressure_batch_raw(data,7,u0,v0,w0,u1,v1,w1,2) != expected0 + expected1
    ok = 0
  ok != 0

# Exercise accepted and rejected rank-neutral flips plus rank-raising splits.
square_cap = ffw_default_capacity(3) ## i64
square = i64[ffw_state_size(square_cap)]
square_rank = ffw_init_naive_cap(square, 3, square_cap, 1701, 8, 3, 5000, 2000) ## i64
failures += hot_expect("square initializes", square_rank == 27)
failures += hot_expect("square initial density", hot_density_consistent(square))
failures += hot_expect("square pressure plans", hot_pressure_suite(square))

i = 0 ## i64
while i < 30000
  mode = 0 ## i64
  if (i % 5) >= 3
    mode = 1
  z = ffw_try_flip(square, mode) ## i64
  failures += hot_expect("square flip density " + i.to_s(), hot_density_consistent(square))
  if (i % 997) == 0
    failures += hot_expect("square flip exact " + i.to_s(), ffw_verify_current_exact(square, 3) != 0)
  i += 1

i = 0
while i < 200
  z = ffw_try_split(square) ## i64
  failures += hot_expect("square split density " + i.to_s(), hot_density_consistent(square))
  if (i % 31) == 0
    failures += hot_expect("square split exact " + i.to_s(), ffw_verify_current_exact(square, 3) != 0)
  i += 1

failures += hot_expect("square final current exact", ffw_verify_current_exact(square, 3) != 0)
failures += hot_expect("square final best exact", ffw_verify_best_exact(square, 3) != 0)
failures += hot_expect("square final pressure plans", hot_pressure_suite(square))

# Rectangular walking uses the same flip transaction and its own split path.
rect_cap = ffr_default_capacity(2, 2, 5) ## i64
rect = i64[ffr_state_size(rect_cap)]
rect_rank = ffr_init_naive_cap(rect, 2, 2, 5, rect_cap, 1907, 8, 3, 5000, 2000) ## i64
failures += hot_expect("rect initializes", rect_rank == 20)
failures += hot_expect("rect initial density", hot_density_consistent(rect))
failures += hot_expect("rect pressure plans", hot_pressure_suite(rect))

i = 0
while i < 30000
  mode = 0
  if (i % 5) >= 3
    mode = 1
  z = ffw_try_flip(rect, mode) ## i64
  failures += hot_expect("rect flip density " + i.to_s(), hot_density_consistent(rect))
  if (i % 997) == 0
    failures += hot_expect("rect flip exact " + i.to_s(), ffr_verify_current_exact(rect, 2, 2, 5) != 0)
  i += 1

i = 0
while i < 200
  z = ffr_try_split(rect) ## i64
  failures += hot_expect("rect split density " + i.to_s(), hot_density_consistent(rect))
  if (i % 31) == 0
    failures += hot_expect("rect split exact " + i.to_s(), ffr_verify_current_exact(rect, 2, 2, 5) != 0)
  i += 1

# Simulate an exact external strategy: split one term without touching the
# accumulator, then use the exhaustive adoption gate as its synchronization
# point.  The worse-rank candidate is intentionally not adopted.
slot = rect[rect[50]] ## i64
old_u = rect[rect[44] + slot] ## i64
old_v = rect[rect[45] + slot] ## i64
old_w = rect[rect[46] + slot] ## i64
part_u = old_u ^ 3 ## i64
if part_u == 0
  part_u = old_u ^ 5
other_u = old_u ^ part_u ## i64
before = rect[6] ## i64
rank = before ## i64
rank = ffw_toggle(rect, old_u, old_v, old_w, rank)
rank = ffw_toggle(rect, part_u, old_v, old_w, rank)
rank = ffw_toggle(rect, other_u, old_v, old_w, rank)
rect[6] = rank
failures += hot_expect("external rect identity exact", ffr_verify_current_exact(rect, 2, 2, 5) != 0)
z = ffr_adopt_current(rect, 1) ## i64
failures += hot_expect("external rect density refresh", hot_density_consistent(rect))

failures += hot_expect("rect final current exact", ffr_verify_current_exact(rect, 2, 2, 5) != 0)
failures += hot_expect("rect final best exact", ffr_verify_best_exact(rect, 2, 2, 5) != 0)
failures += hot_expect("rect final pressure plans", hot_pressure_suite(rect))

if failures > 0
  << "metaflip scheme hot path: " + failures.to_s() + " failure(s)"
  exit(1)

<< "metaflip scheme hot path: ok"
