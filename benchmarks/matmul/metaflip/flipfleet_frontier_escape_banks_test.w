use metaflip_worker
use flipfleet_basin_identity
use flipfleet_bank_policy
use flipfleet_frontier_escape_banks

failures = 0 ## i64

-> fffebt_expect(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    return 1
  0

-> fffebt_contains_id(states, identity) i64
  i = 0 ## i64
  while i < states.size()
    if ffbi_best_id(states[i]) == identity
      return 1
    i += 1
  0

-> fffebt_same_ids(left, right) i64
  if left.size() != right.size()
    return 0
  i = 0 ## i64
  while i < left.size()
    if fffebt_contains_id(right, ffbi_best_id(left[i])) == 0
      return 0
    i += 1
  1

# The live scalar scheduler is finite and covers every source/kind/nonce cell
# exactly once before refusing further work in that rank generation.
schedule_sources = 10 ## i64
schedule_target = fffeb_schedule_target(schedule_sources) ## i64
schedule_seen = i64[schedule_target]
schedule_out = i64[3]
schedule_step = 0 ## i64
while schedule_step < schedule_target
  failures += fffebt_expect("finite schedule decode", fffeb_schedule_decode(schedule_step, schedule_sources, schedule_out) == 1)
  schedule_cell = ((schedule_out[2] * 5 + schedule_out[1] - 1) * schedule_sources) + schedule_out[0] ## i64
  failures += fffebt_expect("finite schedule unique", schedule_cell >= 0 && schedule_cell < schedule_target && schedule_seen[schedule_cell] == 0)
  schedule_seen[schedule_cell] = 1
  schedule_step += 1
failures += fffebt_expect("finite schedule target", schedule_target == 300 && fffeb_schedule_target(16) == 480)
failures += fffebt_expect("finite schedule stops", fffeb_schedule_decode(schedule_target, schedule_sources, schedule_out) == 0)

root = "benchmarks/matmul/metaflip" ## String
n = 4 ## i64
capacity = 96 ## i64
state_size = ffw_state_size(capacity) ## i64
dslack = 4 ## i64
cycles = 4 ## i64
workq = 10000 ## i64
wanderq = 2000 ## i64

d450 = i64[state_size]
d677 = i64[state_size]
r450 = ffw_load_scheme_cap(d450, root + "/matmul_4x4_rank47_d450_gf2.txt", n, capacity, 17, dslack, cycles, workq, wanderq) ## i64
r677 = ffw_load_scheme_cap(d677, root + "/matmul_4x4_rank47_d677_flips_gf2.txt", n, capacity, 19, dslack, cycles, workq, wanderq) ## i64
failures += fffebt_expect("frontiers exact rank47", r450 == 47 && r677 == 47 && ffw_verify_best_exact(d450, n) == 1 && ffw_verify_best_exact(d677, n) == 1)
failures += fffebt_expect("frontiers are distinct basins", ffbi_best_id(d450) != ffbi_best_id(d677))

near1 = []
near1_signatures = []
near1_uses = []
near1_successes = []
near2 = []
near2_signatures = []
near2_uses = []
near2_successes = []
near_counters = i64[5]
family_counters = i64[6]

# Seed the existing bank from d450 exactly as the coordinator does today.
d450_admitted = fffeb_append_source(d450, 47, 0, n, capacity, state_size, dslack, cycles, workq, wanderq, 6, near1, near1_signatures, near1_uses, near1_successes, 32, near2, near2_signatures, near2_uses, near2_successes, 32, 8, 2, near_counters, family_counters) ## i64
failures += fffebt_expect("d450 makes shoulders", d450_admitted > 0 && near1.size() > 0)
before_count = near1.size() ## i64
preserved_id = ffbi_best_id(near1[0]) ## i64

# Appending d677 must not clear d450, and it must contribute a genuinely new
# rank-48 shoulder under the same production caps and diversity policy.
d677_admitted = fffeb_append_source(d677, 47, 1, n, capacity, state_size, dslack, cycles, workq, wanderq, 6, near1, near1_signatures, near1_uses, near1_successes, 32, near2, near2_signatures, near2_uses, near2_successes, 32, 8, 2, near_counters, family_counters) ## i64
failures += fffebt_expect("d677 contributes shoulders", d677_admitted > 0 && near1.size() > before_count)
failures += fffebt_expect("d450 shoulder preserved", fffebt_contains_id(near1, preserved_id) == 1)
failures += fffebt_expect("near metadata aligned", near1.size() == near1_signatures.size() && near1.size() == near1_uses.size() && near1.size() == near1_successes.size())
failures += fffebt_expect("two eligible source families", family_counters[0] == 2 && family_counters[1] == 2 && (family_counters[3] + family_counters[4]) == (d450_admitted + d677_admitted))

i = 0 ## i64
while i < near1.size()
  failures += fffebt_expect("retained shoulder exact rank48", ffw_best_rank(near1[i]) == 48 && ffw_verify_best_exact(near1[i], n) == 1)
  i += 1
i = 0
while i < near2.size()
  failures += fffebt_expect("retained shoulder exact rank49", ffw_best_rank(near2[i]) == 49 && ffw_verify_best_exact(near2[i], n) == 1)
  i += 1

# Six low-cadence one-nonce batches must enumerate the same exact candidate
# support as one eager six-nonce call.  Loose caps/quotas make admission order
# irrelevant so this is a direct coverage contract for the live scheduler.
full_near1 = []
full_near1_signatures = []
full_near1_uses = []
full_near1_successes = []
full_near2 = []
full_near2_signatures = []
full_near2_uses = []
full_near2_successes = []
full_near_counters = i64[5]
full_family_counters = i64[6]
full_total = fffeb_append_source(d677, 47, 1, n, capacity, state_size, dslack, cycles, workq, wanderq, 6, full_near1, full_near1_signatures, full_near1_uses, full_near1_successes, 64, full_near2, full_near2_signatures, full_near2_uses, full_near2_successes, 64, 64, 2, full_near_counters, full_family_counters) ## i64

lazy_near1 = []
lazy_near1_signatures = []
lazy_near1_uses = []
lazy_near1_successes = []
lazy_near2 = []
lazy_near2_signatures = []
lazy_near2_uses = []
lazy_near2_successes = []
lazy_near_counters = i64[5]
lazy_family_counters = i64[6]
lazy_total = 0 ## i64
nonce = 0 ## i64
while nonce < 6
  lazy_total += fffeb_append_source_nonce(d677, 47, 1, nonce, n, capacity, state_size, dslack, cycles, workq, wanderq, lazy_near1, lazy_near1_signatures, lazy_near1_uses, lazy_near1_successes, 64, lazy_near2, lazy_near2_signatures, lazy_near2_uses, lazy_near2_successes, 64, 64, 2, lazy_near_counters, lazy_family_counters)
  nonce += 1
failures += fffebt_expect("lazy batches preserve constructed coverage", lazy_family_counters[2] == full_family_counters[2])
failures += fffebt_expect("lazy batches preserve near1 set", fffebt_same_ids(full_near1, lazy_near1) == 1)
failures += fffebt_expect("lazy batches preserve near2 set", fffebt_same_ids(full_near2, lazy_near2) == 1)
failures += fffebt_expect("lazy batches preserve admissions", lazy_total == full_total)

single_near1 = []
single_near1_signatures = []
single_near1_uses = []
single_near1_successes = []
single_near2 = []
single_near2_signatures = []
single_near2_uses = []
single_near2_successes = []
single_near_counters = i64[5]
single_family_counters = i64[6]
single_total = 0 ## i64
nonce = 0
while nonce < 6
  kind = 1 ## i64
  while kind <= 5
    single_total += fffeb_append_source_kind_nonce(d677, 47, 1, kind, nonce, n, capacity, state_size, dslack, cycles, workq, wanderq, single_near1, single_near1_signatures, single_near1_uses, single_near1_successes, 64, single_near2, single_near2_signatures, single_near2_uses, single_near2_successes, 64, 64, 2, single_near_counters, single_family_counters)
    kind += 1
  nonce += 1
failures += fffebt_expect("single-kind schedule preserves constructed coverage", single_family_counters[2] == full_family_counters[2])
failures += fffebt_expect("single-kind schedule preserves near1 set", fffebt_same_ids(full_near1, single_near1) == 1)
failures += fffebt_expect("single-kind schedule preserves near2 set", fffebt_same_ids(full_near2, single_near2) == 1)
failures += fffebt_expect("single-kind schedule preserves admissions", single_total == full_total)

# Exercise the path-level integration API and its per-source accounting.
paths = []
paths.push("benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt")
paths.push("benchmarks/matmul/metaflip/matmul_4x4_rank47_d677_flips_gf2.txt")
path_near1 = []
path_near1_signatures = []
path_near1_uses = []
path_near1_successes = []
path_near2 = []
path_near2_signatures = []
path_near2_uses = []
path_near2_successes = []
path_near_counters = i64[5]
path_family_counters = i64[6]
source_admissions = []
path_total = fffeb_append_frontier_paths(".", paths, d450, n, capacity, state_size, dslack, cycles, workq, wanderq, 6, path_near1, path_near1_signatures, path_near1_uses, path_near1_successes, 32, path_near2, path_near2_signatures, path_near2_uses, path_near2_successes, 32, 8, 2, path_near_counters, source_admissions, path_family_counters) ## i64
failures += fffebt_expect("path helper visits both", source_admissions.size() == 2 && source_admissions[0] > 0 && source_admissions[1] > 0 && path_total == source_admissions[0] + source_admissions[1])
failures += fffebt_expect("path helper fills rank48 signature quota", path_near1.size() == 8 && path_near1_signatures.size() == path_near1.size())

if failures > 0
  << "flipfleet_frontier_escape_banks_test: " + failures.to_s() + " failure(s)"
  exit(1)
<< "flipfleet_frontier_escape_banks_test: d450=" + d450_admitted.to_s() + " d677=" + d677_admitted.to_s() + " retained-r48=" + near1.size().to_s() + " retained-r49=" + near2.size().to_s()
