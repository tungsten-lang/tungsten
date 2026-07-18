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

-> hot_hash_mix(hash, value) (i64 i64) i64
  x = (hash ^ value) & 9223372036854775807 ## i64
  (((x << 13) & 9223372036854775807) ^ (x >> 7) ^ ((x << 3) & 9223372036854775807)) & 9223372036854775807

-> hot_trajectory_hash(st) (i64[]) i64
  digest = 7809847782465536322 ## i64
  i = 0 ## i64
  while i < st[6]
    slot = st[st[50] + i] ## i64
    digest = hot_hash_mix(digest, st[st[44] + slot])
    digest = hot_hash_mix(digest, st[st[45] + slot])
    digest = hot_hash_mix(digest, st[st[46] + slot])
    i += 1
  digest = hot_hash_mix(digest, st[6])
  digest = hot_hash_mix(digest, st[7])
  digest = hot_hash_mix(digest, st[8])
  digest = hot_hash_mix(digest, st[13])
  digest = hot_hash_mix(digest, st[21])
  digest = hot_hash_mix(digest, st[22])
  digest = hot_hash_mix(digest, st[23])
  digest = hot_hash_mix(digest, st[36])
  hot_hash_mix(digest, st[64])

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

# Baseline two-pass partner selection retained in the regression test so the
# singleton-bucket shortcut is checked against every live slot, including
# buckets that contain unrelated hash collisions and core min-slot filters.
-> hot_partner_reference(st, axis, slot, random_word, min_slot) (i64[] i64 i64 i64 i64) i64
  head = st[53] ## i64
  nexto = st[56] ## i64
  factoro = st[44] ## i64
  if axis == 1
    head = st[54]
    nexto = st[58]
    factoro = st[45]
  if axis == 2
    head = st[55]
    nexto = st[60]
    factoro = st[46]
  key = st[factoro + slot] ## i64
  count = ffw_chain_count_min(st,head,nexto,factoro,key,slot,min_slot) ## i64
  if count > 0
    want = (random_word * count) >> 31 ## i64
    return ffw_chain_pick_min(st,head,nexto,factoro,key,slot,want,min_slot)
  0 - 1

-> hot_partner_suite(st) (i64[]) bool
  i = 0 ## i64
  while i < st[6]
    slot = st[st[50] + i] ## i64
    axis = 0 ## i64
    while axis < 3
      sample = 0 ## i64
      while sample < 4
        word = 0 ## i64
        min_slot = 0 ## i64
        if sample == 1
          word = 715827882
        if sample == 2
          word = 2147483647
        if sample == 3
          word = 1431655765
          min_slot = st[4] / 3
        expected = hot_partner_reference(st,axis,slot,word,min_slot) ## i64
        actual = ffw_pick_partner_min(st,axis,slot,word,min_slot) ## i64
        if actual != expected
          return false
        sample += 1
      axis += 1
    i += 1
  true

# Exercise accepted and rejected rank-neutral flips plus rank-raising splits.
square_cap = ffw_default_capacity(3) ## i64
square = i64[ffw_state_size(square_cap)]
square_rank = ffw_init_naive_cap(square, 3, square_cap, 1701, 8, 3, 5000, 2000) ## i64
failures += hot_expect("square initializes", square_rank == 27)
failures += hot_expect("square initial density", hot_density_consistent(square))
failures += hot_expect("square pressure plans", hot_pressure_suite(square))
failures += hot_expect("square partner selection", hot_partner_suite(square))

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
failures += hot_expect("square final partner selection", hot_partner_suite(square))
failures += hot_expect("square fixed trajectory", hot_trajectory_hash(square) == 5608517473452130838)

# Rectangular walking uses the same flip transaction and its own split path.
rect_cap = ffr_default_capacity(2, 2, 5) ## i64
rect = i64[ffr_state_size(rect_cap)]
rect_rank = ffr_init_naive_cap(rect, 2, 2, 5, rect_cap, 1907, 8, 3, 5000, 2000) ## i64
failures += hot_expect("rect initializes", rect_rank == 20)
failures += hot_expect("rect initial density", hot_density_consistent(rect))
failures += hot_expect("rect pressure plans", hot_pressure_suite(rect))
failures += hot_expect("rect partner selection", hot_partner_suite(rect))

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
failures += hot_expect("rect final partner selection", hot_partner_suite(rect))
failures += hot_expect("rect fixed trajectory", hot_trajectory_hash(rect) == 4244222856608978680)

if failures > 0
  << "metaflip scheme hot path: " + failures.to_s() + " failure(s)"
  exit(1)

<< "metaflip scheme hot path: ok"
