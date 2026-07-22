use ../lib/metaflip/fleet/seven_by_seven
use ../lib/metaflip/seeds/shoulders

failures = 0 ## i64

-> seven_shoulder_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL 7x7 shoulder inventory: " + label
    return 1
  0

runtime_root = __DIR__ + "/../lib/metaflip"
capacity = 320 ## i64
state_size = ffw_state_size(capacity) ## i64
best = i64[state_size]
best_path = runtime_root + "/seeds/gf2/matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"
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

# The canonical d2946 density leader and novel AWS d3092 shoulder enter through
# the generic profile inventory after the four historical 7x7 shoulders. This
# mirrors production ordering and proves both survive the ordinary
# signature/max-min admission policy rather than merely existing on disk.
profile_admitted = ffps_add_profile_near_seeds(runtime_root, best, 7, capacity, state_size, 0, 1, 1, 1, near1, near1_signatures, near1_uses, near1_successes, 16, [], [], [], [], 16, 4, near_counters) ## i64
failures += seven_shoulder_expect("both profile rank-248 shoulders are admitted", profile_admitted == 2 && near1.size() == 6)
aws_density_seen = 0 ## i64
aws_local_seen = 0 ## i64
aws_density_distance = 0 ## i64
aws_local_distance = 0 ## i64
i = 0
while i < near1.size()
  if ffw_best_bits(near1[i]) == 2946
    aws_density_seen = 1
    aws_density_distance = ffbp_distance(best, near1[i])
  if ffw_best_bits(near1[i]) == 3092
    aws_local_seen = 1
    aws_local_distance = ffbp_distance(best, near1[i])
  i += 1
failures += seven_shoulder_expect("profile shoulders retain their audited densities", aws_density_seen == 1 && aws_local_seen == 1)
failures += seven_shoulder_expect("profile shoulders retain remote/local support geometry", aws_density_distance == 495 && aws_local_distance == 19)
all_pair_distance = ffbp_min_distance(near1) ## i64
failures += seven_shoulder_expect("six-shoulder bank remains pairwise distinct", all_pair_distance >= 4)

# The same inventory is deliberately rank-specific: it must not contaminate a
# campaign whose leader has already moved below 247.
best[7] = 246
rejected = ff7_add_known_7x7_rank247_shoulders(runtime_root, best, 7, capacity, state_size, 0, 1, 1, 1, near1, near1_signatures, near1_uses, near1_successes, 16, 4, near_counters) ## i64
failures += seven_shoulder_expect("inventory is gated by the live leader rank", rejected == 0 && near1.size() == 6)

if failures > 0
  exit(1)
<< "PASS 7x7 shoulder inventory historical=" + admitted.to_s() + " profile=" + profile_admitted.to_s() + " exact=" + near1.size().to_s() + " pair_min=" + all_pair_distance.to_s() + " leader_distance=" + aws_density_distance.to_s() + "/" + aws_local_distance.to_s()
