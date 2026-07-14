use metaflip_worker
use flipfleet_cpu_experiments

-> ffcr_test_expect(name, condition)
  if condition == 0
    << "FAIL " + name
    exit(1)

controls = i64[7]
quotas = i64[2]
i = 0 ## i64
while i < ffcr_arm_count()
  z = ffcr_fill_arm(i, 1000, 250, controls, quotas) ## i64
  ffcr_test_expect("valid work quota", quotas[0] > 0)
  ffcr_test_expect("valid wander quota", quotas[1] > 0)
  ffcr_test_expect("valid band range", controls[6] > controls[5])
  i += 1
ffcr_test_expect("flip-only disables split", ffcr_fill_arm(3, 1000, 250, controls, quotas) == 3 && controls[0] == 0)

pulls = i64[8]
exposure = i64[8]
novel = i64[8]
returns = i64[8]
drops = i64[8]
i = 0
while i < 8
  ffcr_test_expect("untried rotation", ffcr_select_arm(i, pulls, exposure, novel, returns, drops) == i)
  z = ffcr_record_lease(i, 1000000, 0, 0, 0, pulls, exposure, novel, returns, drops) ## i64
  i += 1
novel[5] = 3
returns[5] = 0
returns[2] = 4
ffcr_test_expect("yield beats return hazard", ffcr_select_arm(8, pulls, exposure, novel, returns, drops) == 5)
drops[3] = 1
ffcr_test_expect("rank drop dominates", ffcr_select_arm(9, pulls, exposure, novel, returns, drops) == 3)

n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
z = ffw_init_naive_cap(state, n, capacity, 31, 6, 4, 1000, 250) ## i64
z = ffcr_apply_arm(state, 1, 1000, 250, controls) ## i64
before = ffw_moves(state) ## i64
z = ffw_walk_tuned(state, 2000, controls) ## i64
ffcr_test_expect("tuned worker advances", ffw_moves(state) - before == 2000)
ffcr_test_expect("tuned worker exact", ffw_verify_best_exact(state, n) == 1)

recent = i64[64]
stats = i64[9]
before = ffw_moves(state)
z = ffw_walk_cycle_watch(state, 2000, recent, 64, stats) ## i64
ffcr_test_expect("cycle watcher advances", ffw_moves(state) - before == 2000)
ffcr_test_expect("cycle watcher initialized", stats[8] == 1 && stats[1] > 0)
ffcr_test_expect("cycle accepted accounting", stats[5] <= ffw_accepted(state))

<< "flipfleet_cpu_experiments_test: all checks passed"
