# Correctness and isolation contract for the opt-in CPU axis-sweep racer.
# The default walker keeps its historical trajectory test in
# scheme_hotpath_test.w; this file proves that retrying alternate axes remains
# exact and actually rescues a first-axis collision miss on a real scheme.

use ../lib/metaflip/rect
use ../lib/metaflip/fleet/cpu_experiments
use ../lib/metaflip/fleet/cpu_pool

failures = 0 ## i64

-> asrt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    return 1
  0

-> asrt_density_ok(st) (i64[]) bool
  ffw_view_bits(st, st[44], st[45], st[46], st[50], st[6]) == st[36] + st[64]

-> asrt_mix(hash, value) (i64 i64) i64
  x = (hash ^ value) & 9223372036854775807 ## i64
  (((x << 13) & 9223372036854775807) ^ (x >> 7) ^ ((x << 3) & 9223372036854775807)) & 9223372036854775807

-> asrt_trajectory(st) (i64[]) i64
  digest = 4972681700960895113 ## i64
  i = 0 ## i64
  while i < st[6]
    slot = st[st[50] + i] ## i64
    digest = asrt_mix(digest, st[st[44] + slot])
    digest = asrt_mix(digest, st[st[45] + slot])
    digest = asrt_mix(digest, st[st[46] + slot])
    i += 1
  digest = asrt_mix(digest, st[6])
  digest = asrt_mix(digest, st[7])
  digest = asrt_mix(digest, st[8])
  digest = asrt_mix(digest, st[20])
  digest = asrt_mix(digest, st[21])
  digest = asrt_mix(digest, st[22])
  digest = asrt_mix(digest, st[23])
  asrt_mix(digest, st[64])

root = __DIR__ + "/../lib/metaflip/seeds/gf2/" ## String
paths = ["matmul_3x3_rank23_d139_gf2.txt",
         "matmul_5x5_rank93_d1155_gf2.txt",
         "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"]
dims = [3, 5, 7]
ranks = [23, 93, 247]

case_index = 0 ## i64
while case_index < paths.size()
  n = dims[case_index] ## i64
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state, root + paths[case_index], n, capacity, 76101 + n, 6, 4, 1000000000, 200000000) ## i64
  failures += asrt_expect(n.to_s() + "x" + n.to_s() + " load", rank == ranks[case_index])
  before_proposals = ffw_proposals(state) ## i64
  i = 0 ## i64
  while i < 30000
    mode = 0 ## i64
    if (i % 5) >= 3
      mode = 1
    z = ffw_try_flip_axis_sweep(state, mode) ## i64
    if (i % 997) == 0
      failures += asrt_expect(n.to_s() + "x" + n.to_s() + " exact " + i.to_s(), ffw_verify_current_exact(state, n) == 1)
      failures += asrt_expect(n.to_s() + "x" + n.to_s() + " density " + i.to_s(), asrt_density_ok(state))
    i += 1
  failures += asrt_expect(n.to_s() + "x" + n.to_s() + " proposal accounting", ffw_proposals(state) - before_proposals == 30000)
  failures += asrt_expect(n.to_s() + "x" + n.to_s() + " final exact", ffw_verify_current_exact(state, n) == 1 && ffw_verify_best_exact(state, n) == 1)
  failures += asrt_expect(n.to_s() + "x" + n.to_s() + " final density", asrt_density_ok(state))
  if n == 5
    sweep_trajectory = asrt_trajectory(state) ## i64
    failures += asrt_expect("5x5 fixed sweep trajectory", sweep_trajectory == 2724333486437994032)
  case_index += 1

rect_capacity = ffr_default_capacity(2, 2, 5) ## i64
rect = i64[ffr_state_size(rect_capacity)]
rect_rank = ffr_load_scheme_cap(rect, root + "matmul_2x2x5_rank18_d84_gf2.txt", 2, 2, 5, rect_capacity, 76025, 6, 4, 1000000000, 200000000) ## i64
i = 0
while i < 30000
  mode = 0 ## i64
  if (i % 5) >= 3
    mode = 1
  z = ffw_try_flip_axis_sweep(rect, mode) ## i64
  i += 1
failures += asrt_expect("2x2x5 natural support", rect_rank == 18 && ffr_verify_current_exact(rect, 2, 2, 5) == 1 && ffr_verify_best_exact(rect, 2, 2, 5) == 1 && asrt_density_ok(rect))

# Search a bounded deterministic seed range for a real proposal whose chosen
# axis is empty but whose same first term has a collision on another axis.
# Baseline and sweep start byte-identically; only the opt-in retry may turn the
# proposal-level miss into a legal accepted-or-rejected flip.
n = 3
capacity = ffw_default_capacity(n)
state_size = ffw_state_size(capacity)
witness = 0 ## i64
seed = 1 ## i64
while seed <= 4096 && witness == 0
  baseline = i64[state_size]
  sweep = i64[state_size]
  rb = ffw_load_scheme_cap(baseline, root + paths[0], n, capacity, seed, 6, 4, 1000000000, 200000000) ## i64
  rs = ffw_load_scheme_cap(sweep, root + paths[0], n, capacity, seed, 6, 4, 1000000000, 200000000) ## i64
  if rb == 23 && rs == 23
    zb = ffw_try_flip(baseline, 0) ## i64
    zs = ffw_try_flip_axis_sweep(sweep, 0) ## i64
    if ffw_partner_misses(baseline) == 1 && ffw_partner_misses(sweep) == 0
      if ffw_accepted(sweep) + ffw_rejected(sweep) == 1
        witness = seed
        failures += asrt_expect("rescued proposal exact", ffw_verify_current_exact(sweep, n) == 1)
        failures += asrt_expect("rescued proposal density", asrt_density_ok(sweep))
  seed += 1
failures += asrt_expect("alternate axis rescues a real first-axis miss", witness > 0)

# Pin the adaptive-policy and persistent-worker dispatch. A mode-2 worker with
# the arm's negative cadence tag must follow the exact same deterministic
# trajectory as a direct axis-sweep call; ordinary nonnegative controls remain
# on ffw_walk_tuned.
controls = i64[7]
quotas = i64[2]
selected = ffcr_fill_arm(10, 1000000000, 200000000, controls, quotas) ## i64
failures += asrt_expect("adaptive arm inventory", ffcr_arm_count() == 11 && selected == 10 && ffcr_arm_name(10) == "axis-sweep")
failures += asrt_expect("adaptive arm dispatch tag", controls[0] == 0 - 2000)
edge_free_capacity = ffw_default_capacity(4) ## i64
edge_free = i64[ffw_state_size(edge_free_capacity)]
redge = ffw_load_scheme_cap(edge_free, root + "matmul_4x4_rank47_d450_gf2.txt", 4, edge_free_capacity, 95000, 6, 4, 1000000000, 200000000) ## i64
edge_setup = i64[7]
edge_arm = ffcr_apply_arm_measured(edge_free, 10, 1000000000, 200000000, controls, edge_setup) ## i64
failures += asrt_expect("zero-edge arm uses baseline", redge == 47 && edge_arm == 10 && ffw_partnerable_incidences(edge_free) == 0 && controls[0] == 2000)
selected = ffcr_fill_arm(10, 1000000000, 200000000, controls, quotas)
split_probe = i64[state_size]
rsplit = ffw_load_scheme_cap(split_probe, root + paths[0], 3, capacity, 95001, 6, 4, 1000000000, 200000000) ## i64
split_probe[10] = 8
split_probe[13] = 2000
split_probe[14] = 1000000000
split_before = ffw_split_attempts(split_probe) ## i64
z = ffw_walk_axis_sweep_tuned(split_probe, 1, controls) ## i64
failures += asrt_expect("dispatch tag preserves split cadence", rsplit == 23 && ffw_split_attempts(split_probe) == split_before + 1 && ffw_verify_current_exact(split_probe, 3) == 1)
direct = i64[state_size]
pooled = i64[state_size]
rd = ffw_load_scheme_cap(direct, root + paths[0], 3, capacity, 95003, 6, 4, 1000000000, 200000000) ## i64
rp = ffw_load_scheme_cap(pooled, root + paths[0], 3, capacity, 95003, 6, 4, 1000000000, 200000000) ## i64
z = ffw_walk_axis_sweep_tuned(direct, 20000, controls) ## i64
state_slots = []
state_slots.push(pooled)
round_steps = i64[1]
round_steps[0] = 20000
core_slots = i64[1]
recent = i64[64]
cycle_stats = i64[9]
elapsed_ms = i64[1]
start_channel = Channel.new(1)
done_channel = Channel.new(1)
worker = ffcp_spawn(state_slots, 0, 2, round_steps, core_slots, controls, recent, 64, cycle_stats, elapsed_ms, start_channel, done_channel)
start_channel.send(1)
completed = done_channel.recv() ## i64
start_channel.send(0)
joined = ccall("w_thread_join_release", worker)
failures += asrt_expect("worker dispatch completes", rd == 23 && rp == 23 && completed == 0)
failures += asrt_expect("worker dispatch trajectory", asrt_trajectory(pooled) == asrt_trajectory(direct))
failures += asrt_expect("worker dispatch exact", ffw_verify_current_exact(pooled, 3) == 1 && asrt_density_ok(pooled))

if failures > 0
  << "metaflip axis sweep racer: " + failures.to_s() + " failure(s)"
  exit(1)

<< "metaflip axis sweep racer: ok witness_seed=" + witness.to_s()
