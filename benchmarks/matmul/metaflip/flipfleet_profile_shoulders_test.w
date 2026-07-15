use flipfleet_profile_shoulders

-> ffpst_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

root = capture("pwd").strip()
n = 4 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
best = i64[state_size]
best_path = root + "/benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt"
best_rank = ffw_load_scheme_cap(best, best_path, n, capacity, 71, 4, 4, 1000, 250) ## i64
ffpst_expect("rank47 leader exact", best_rank == 47 && ffw_verify_best_exact(best, n) == 1)

near1 = []
near1_signatures = []
near1_uses = []
near1_successes = []
near2 = []
near2_signatures = []
near2_uses = []
near2_successes = []
counters = i64[5]
admitted = ffps_add_profile_near_seeds(root, best, n, capacity, state_size, 4, 4, 1000, 250, near1, near1_signatures, near1_uses, near1_successes, 8, near2, near2_signatures, near2_uses, near2_successes, 8, 4, counters) ## i64
ffpst_expect("one signed shoulder admitted", admitted == 1 && near1.size() == 0 && near2.size() == 1)
ffpst_expect("signed shoulder full gate", ffw_best_rank(near2[0]) == 49 && ffw_best_bits(near2[0]) == 432 && ffw_verify_best_exact(near2[0], n) == 1)
ffpst_expect("shoulder cannot replace fleet best", ffw_best_rank(near2[0]) > ffw_best_rank(best))
ffpst_expect("signed shoulder far from leader", ffbp_distance(best, near2[0]) == 96)

# A changed frontier makes r49 debt +3, so it cannot be mislabeled as near2.
naive = i64[state_size]
naive_rank = ffw_init_naive_cap(naive, n, capacity, 73, 4, 4, 1000, 250) ## i64
ffpst_expect("naive exact", naive_rank == 64 && ffw_verify_best_exact(naive, n) == 1)
empty1 = []
empty1_signatures = []
empty1_uses = []
empty1_successes = []
empty2 = []
empty2_signatures = []
empty2_uses = []
empty2_successes = []
empty_counters = i64[5]
stale = ffps_add_profile_near_seeds(root, naive, n, capacity, state_size, 4, 4, 1000, 250, empty1, empty1_signatures, empty1_uses, empty1_successes, 8, empty2, empty2_signatures, empty2_uses, empty2_successes, 8, 4, empty_counters) ## i64
ffpst_expect("delta mismatch rejected", stale == 0 && empty1.size() == 0 && empty2.size() == 0)

<< "flipfleet_profile_shoulders_test: all checks passed"
