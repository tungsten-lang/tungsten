use ../lib/metaflip/rect
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
  z = ffr2278_expect(label + " three controlled-debt restart doors", ffrp_frontier_seed_count(2, 2, p) == 3 && ffrp_frontier_seed_rel(2, 2, p, 0) == ffrp_seed_rel(2, 2, p))
  slot = 0 ## i64
  while slot < 3
    door = i64[ffr_state_size(cap)]
    door_path = root + "/" + ffrp_frontier_seed_rel(2, 2, p, slot) ## String
    door_rank = ffr_load_scheme_cap(door, door_path, 2, 2, p, cap, 92800 + p * 10 + slot, 4, 4, 1000, 250) ## i64
    z = ffr2278_expect(label + " restart door exact " + slot.to_s(), door_rank == expected_rank + slot && ffr_verify_best_exact(door, 2, 2, p) == 1)
    slot += 1
  rank

root = __DIR__ + "/../lib/metaflip"
r7 = ffr2278_check(root, 7, 25, 132, 227, 26) ## i64
r8 = ffr2278_check(root, 8, 28, 160, 228, 28) ## i64
<< "PASS explicit 2x2x7/2x2x8 profiles ranks=" + r7.to_s() + "/" + r8.to_s()
