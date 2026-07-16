use ../lib/metaflip/rect
use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/rect/policy

-> ffr229_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL 2x2x9 profile: " + label
    exit(1)
  1

-> ffr229_overlap(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  overlap = 0 ## i64
  i = 0 ## i64
  while i < left_count
    j = 0 ## i64
    while j < right_count
      if left_u[i] == right_u[j] && left_v[i] == right_v[j] && left_w[i] == right_w[j]
        overlap += 1
        j = right_count
      j += 1
    i += 1
  overlap

root = __DIR__ + "/../lib/metaflip"
seed = root + "/" + ffrp_seed_rel(2, 2, 9)
cap = ffr_default_capacity(2, 2, 9) ## i64
state = i64[ffr_state_size(cap)]
rank = ffr_load_scheme_cap(state, seed, 2, 2, 9, cap, 92209, 4, 4, 1000, 250) ## i64

z = ffr229_expect("explicit profile enabled", ffrp_supported(2, 2, 9) == 1 && ffrp_supported_label("2x2x9") == 1)
z = ffr229_expect("record and strict target", ffrp_record_rank(2, 2, 9) == 32 && ffrp_target_rank(2, 2, 9) == 31)
z = ffr229_expect("rank-32 imported seed", rank == 32 && ffr_best_rank(state) == 32)
z = ffr229_expect("independent full tensor gate", ffr_verify_best_exact(state, 2, 2, 9) == 1)
z = ffr229_expect("reduced density", ffr_best_bits(state) == 156)
z = ffr229_expect("4/18/18-bit factors", ffr_u_width(state) == 4 && ffr_v_width(state) == 18 && ffr_w_width(state) == 18)
z = ffr229_expect("safe Metal geometry", ffrgb_geometry_valid(2, 2, 9) == 1 && ffrgb_cap(2, 2, 9) == 64 && ffrgb_shared_bytes(2, 2, 9) == 12288)
z = ffr229_expect("explicit portfolio priority", ffrpp_default_base_weight(229) == 30 && ffrpp_default_leverage(229) == 800 && ffrpp_default_gpu_capable(229) == 1)
z = ffr229_expect("five exact restart doors", ffrp_frontier_seed_count(2, 2, 9) == 5)

base_u = i64[cap]
base_v = i64[cap]
base_w = i64[cap]
z = ffr229_expect("base export", ffw_export_best(state, base_u, base_v, base_w) == 32)
slot = 1 ## i64
while slot < 5
  door = i64[ffr_state_size(cap)]
  door_path = root + "/" + ffrp_frontier_seed_rel(2, 2, 9, slot)
  door_rank = ffr_load_scheme_cap(door, door_path, 2, 2, 9, cap, 92209 + slot, 4, 4, 1000, 250) ## i64
  expected_rank = 32 ## i64
  expected_density = 156 ## i64
  if slot == 3
    expected_rank = 33
    expected_density = 159
  if slot == 4
    expected_rank = 34
    expected_density = 165
  z = ffr229_expect("restart door exact " + slot.to_s(), door_rank == expected_rank && ffr_best_bits(door) == expected_density && ffr_verify_best_exact(door, 2, 2, 9) == 1)
  door_u = i64[cap]
  door_v = i64[cap]
  door_w = i64[cap]
  z = ffr229_expect("restart door export " + slot.to_s(), ffw_export_best(door, door_u, door_v, door_w) == expected_rank)
  overlap = ffr229_overlap(base_u, base_v, base_w, 32, door_u, door_v, door_w, expected_rank) ## i64
  if slot == 1
    z = ffr229_expect("cycle door is distant", overlap == 4)
  if slot == 2
    z = ffr229_expect("reverse door is disjoint", overlap == 0)
  if slot >= 3
    z = ffr229_expect("rank-debt door is not the base", overlap < 32)
  slot += 1

<< "PASS 2x2x9 explicit profile rank=" + rank.to_s() + " density=" + ffr_best_bits(state).to_s()
