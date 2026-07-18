use ../lib/metaflip/rect
use ../lib/metaflip/rect/doors
use ../lib/metaflip/kernels/bundles/rect
use ../lib/metaflip/rect/policy

-> ffr2278_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL 2x2x7/2x2x8 profile: " + label
    exit(1)
  1

-> ffr2278_check(root, p, expected_rank, expected_density, shape_code, expected_weight) (String i64 i64 i64 i64 i64) i64
  seed = root + "/" + ffrp_seed_rel(2, 2, p)
  cap = ffr_default_capacity(2, 2, p) ## i64
  state = i64[ffr_state_size(cap)]
  rank = ffr_load_scheme_cap(state, seed, 2, 2, p, cap, 92700 + p, 4, 4, 1000, 250) ## i64
  label = "2x2x" + p.to_s() ## String
  z = ffr2278_expect(label + " enabled", ffrp_supported(2, 2, p) == 1 && ffrp_supported_label(label) == 1)
  z = ffr2278_expect(label + " record/target", ffrp_record_rank(2, 2, p) == expected_rank && ffrp_target_rank(2, 2, p) == expected_rank - 1)
  z = ffr2278_expect(label + " seed rank", rank == expected_rank && ffr_best_rank(state) == expected_rank)
  z = ffr2278_expect(label + " full exact gate", ffr_verify_best_exact(state, 2, 2, p) == 1)
  z = ffr2278_expect(label + " density", ffr_best_bits(state) == expected_density)
  z = ffr2278_expect(label + " factor widths", ffr_u_width(state) == 4 && ffr_v_width(state) == 2*p && ffr_w_width(state) == 2*p)
  z = ffr2278_expect(label + " Metal geometry", ffrgb_geometry_valid(2, 2, p) == 1 && ffrgb_cap(2, 2, p) == 64 && ffrgb_shared_bytes(2, 2, p) == 12288)
  z = ffr2278_expect(label + " explicit priority", ffrpp_default_base_weight(shape_code) == expected_weight && ffrpp_default_leverage(shape_code) == 1 && ffrpp_default_gpu_capable(shape_code) == 1)
  door_count = 3 ## i64
  if p == 7
    door_count = 4
  z = ffr2278_expect(label + " controlled-debt restart doors", ffrp_frontier_seed_count(2, 2, p) == door_count && ffrp_frontier_seed_rel(2, 2, p, 0) == ffrp_seed_rel(2, 2, p))
  slot = 0 ## i64
  while slot < door_count
    door = i64[ffr_state_size(cap)]
    door_path = root + "/" + ffrp_frontier_seed_rel(2, 2, p, slot) ## String
    door_rank = ffr_load_scheme_cap(door, door_path, 2, 2, p, cap, 92800 + p * 10 + slot, 4, 4, 1000, 250) ## i64
    expected_door_rank = expected_rank + slot ## i64
    if p == 7 && slot > 0
      expected_door_rank -= 1
    z = ffr2278_expect(label + " restart door exact " + slot.to_s(), door_rank == expected_door_rank && ffr_verify_best_exact(door, 2, 2, p) == 1)
    slot += 1
  rank

root = __DIR__ + "/../lib/metaflip"
r7 = ffr2278_check(root, 7, 25, 128, 227, 26) ## i64
r8 = ffr2278_check(root, 8, 28, 160, 228, 28) ## i64

# The former density-132 leader remains an independently exact rank-R door,
# not a discarded artifact. Its term-set distance from d128 is large enough to
# preserve a genuinely different restart basin.
p7_cap = ffr_default_capacity(2, 2, 7) ## i64
p7_new = i64[ffr_state_size(p7_cap)]
p7_old = i64[ffr_state_size(p7_cap)]
p7_new_rank = ffr_load_scheme_cap(p7_new, root + "/" + ffrp_seed_rel(2, 2, 7), 2, 2, 7, p7_cap, 92901, 4, 4, 1000, 250) ## i64
p7_old_rank = ffr_load_scheme_cap(p7_old, root + "/seeds/gf2/matmul_2x2x7_rank25_catalog_gf2.txt", 2, 2, 7, p7_cap, 92902, 4, 4, 1000, 250) ## i64
z = ffr2278_expect("2x2x7 d128/d132 exact density pair", p7_new_rank == 25 && p7_old_rank == 25 && ffr_best_bits(p7_new) == 128 && ffr_best_bits(p7_old) == 132 && ffrda_best_distance(p7_new, p7_old) == 42)
<< "PASS explicit 2x2x7/2x2x8 profiles ranks=" + r7.to_s() + "/" + r8.to_s()
