use ../lib/metaflip/fleet/seven_by_seven

failures = 0 ## i64

-> seven_shoulder_expect(label, condition) (String bool) i64
  if condition == 0
    << "FAIL 7x7 shoulder inventory: " + label
    return 1
  0

runtime_root = __DIR__ + "/../lib/metaflip"
capacity = 320 ## i64
state_size = ffw_state_size(capacity) ## i64
best = i64[state_size]
best_path = runtime_root + "/seeds/gf2/matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt"
best_rank = ffw_load_scheme_cap(best, best_path, 7, capacity, 77007, 0, 1, 1, 1) ## i64
failures += seven_shoulder_expect("rank-247 leader loads exactly", best_rank == 247 && ffw_verify_best_exact(best, 7) == 1)

near1 = []
near1_signatures = []
near1_uses = []
near1_successes = []
near_counters = i64[5]
admitted = ff7_add_known_7x7_rank247_shoulders(runtime_root, best, 7, capacity, state_size, 0, 1, 1, 1, near1, near1_signatures, near1_uses, near1_successes, 16, 4, near_counters) ## i64

failures += seven_shoulder_expect("all four packaged rank-248 shoulders are admitted", admitted == 4 && near1.size() == 4)
failures += seven_shoulder_expect("bank metadata follows every admission", near1_signatures.size() == 4 && near1_uses.size() == 4 && near1_successes.size() == 4)
minimum_leader_distance = 999999999 ## i64
i = 0 ## i64
while i < near1.size()
  failures += seven_shoulder_expect("shoulder " + i.to_s() + " is exact rank 248", ffw_best_rank(near1[i]) == 248 && ffw_verify_best_exact(near1[i], 7) == 1)
  leader_distance = ffbp_distance(best, near1[i]) ## i64
  if leader_distance < minimum_leader_distance
    minimum_leader_distance = leader_distance
  i += 1
minimum_pair_distance = ffbp_min_distance(near1) ## i64
failures += seven_shoulder_expect("shoulders are pairwise distinct", minimum_pair_distance >= 4)
failures += seven_shoulder_expect("shoulders differ from the rank-247 leader", minimum_leader_distance >= 3)

# The same inventory is deliberately rank-specific: it must not contaminate a
# campaign whose leader has already moved below 247.
best[7] = 246
rejected = ff7_add_known_7x7_rank247_shoulders(runtime_root, best, 7, capacity, state_size, 0, 1, 1, 1, near1, near1_signatures, near1_uses, near1_successes, 16, 4, near_counters) ## i64
failures += seven_shoulder_expect("inventory is gated by the live leader rank", rejected == 0 && near1.size() == 4)

if failures > 0
  exit(1)
<< "PASS 7x7 shoulder inventory admitted=" + admitted.to_s() + " exact=" + near1.size().to_s() + " pair_min=" + minimum_pair_distance.to_s() + " leader_min=" + minimum_leader_distance.to_s()
