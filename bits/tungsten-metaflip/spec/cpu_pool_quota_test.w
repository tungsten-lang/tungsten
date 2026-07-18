use ../lib/metaflip/scheme
use ../lib/metaflip/fleet/cpu_pool

-> ffcpqt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL cpu pool quota " + label
    exit(1)
  1

elapsed = i64[8]
eligible = i64[8]
scratch = i64[8]
elapsed[0] = 640
elapsed[1] = 11
elapsed[2] = 10
elapsed[3] = 9
elapsed[4] = 12
elapsed[5] = 8
eligible[0] = 1
eligible[1] = 1
eligible[2] = 1
eligible[3] = 1
eligible[4] = 1
eligible[5] = 1

median = ffcp_median_elapsed(elapsed, eligible, 6, scratch) ## i64
z = ffcpqt_expect("lower median ignores tail", median == 10) ## i64

# The 64x tail is corrected immediately to its measured equal-time quota.
slow = ffcp_adapt_round_steps(500000, 640, 10, 500000) ## i64
z = ffcpqt_expect("extreme tail direct correction", slow == 7812)
# Near-target jitter is damped rather than copied into the next round.
near = ffcp_adapt_round_steps(500000, 12, 10, 500000) ## i64
z = ffcpqt_expect("near target smoothing", near == 479166)
# A parked/invalid timing sample leaves its quota unchanged.
z = ffcpqt_expect("zero timing unchanged", ffcp_adapt_round_steps(12345, 0, 10, 500000) == 12345)
# Hard bounds retain slow lanes and cap fast-lane monopolization.
z = ffcpqt_expect("minimum bound", ffcp_adapt_round_steps(500000, 10000000, 1, 500000) == 488)
z = ffcpqt_expect("maximum bound", ffcp_adapt_round_steps(500000, 1, 10000000, 500000) == 875000)

# Excluding a special control lane keeps it from biasing the ordinary target.
eligible[0] = 0
median_without_control = ffcp_median_elapsed(elapsed, eligible, 6, scratch) ## i64
z = ffcpqt_expect("eligibility mask", median_without_control == 10)

# A deterministic cost simulation shows the barrier tail collapsing after one
# observation while all lanes retain positive work.
cost = i64[4]
cost[0] = 1
cost[1] = 1
cost[2] = 2
cost[3] = 64
steps = i64[4]
sim_elapsed = i64[4]
sim_eligible = i64[4]
sim_scratch = i64[4]
i = 0 ## i64
while i < 4
  steps[i] = 500000
  sim_eligible[i] = 1
  sim_elapsed[i] = steps[i] * cost[i] / 500000
  i += 1
sim_target = ffcp_median_elapsed(sim_elapsed, sim_eligible, 4, sim_scratch) ## i64
i = 0
while i < 4
  steps[i] = ffcp_adapt_round_steps(steps[i], sim_elapsed[i], sim_target, 500000)
  i += 1
z = ffcpqt_expect("simulation tail quota", steps[3] == 7812)
z = ffcpqt_expect("simulation lanes retained", steps[0] > 0 && steps[1] > 0 && steps[2] > 0 && steps[3] > 0)

# Coordinator cadence: small fleets preserve exact historical steps; a J188
# launch whose first median epoch is 40ms jumps directly to the measured
# 3-second cadence; an extreme sample is bounded by the 128x cap.
z = ffcpqt_expect("small fleet cadence unchanged", ffcp_epoch_target_ms(32) == 0)
z = ffcpqt_expect("wide fleet threshold cadence", ffcp_epoch_target_ms(33) == 3000 && ffcp_epoch_target_ms(64) == 3000 && ffcp_epoch_target_ms(128) == 3000)
z = ffcpqt_expect("wide fleet cadence", ffcp_epoch_target_ms(188) == 3000)
wide_steps = ffcp_adapt_epoch_steps(500000, 40, 3000, 500000) ## i64
z = ffcpqt_expect("wide first calibration", wide_steps == 37500000)
z = ffcpqt_expect("epoch cap", ffcp_adapt_epoch_steps(500000, 1, 1000000, 500000) == 64000000)
z = ffcpqt_expect("epoch never below nominal", ffcp_adapt_epoch_steps(500000, 4000, 3000, 500000) == 500000)

# Campaign nonce zero is bit-for-bit compatible; nonzero campaigns are stable,
# distinct, and remain inside ffw_seed_rng's 62-bit input domain.
z = ffcpqt_expect("nonce zero identity", ffcp_campaign_seed(1009, 0) == 1009)
nonce_a = ffcp_campaign_seed(1009, 7) ## i64
nonce_b = ffcp_campaign_seed(1009, 8) ## i64
z = ffcpqt_expect("nonce deterministic", nonce_a == ffcp_campaign_seed(1009, 7))
z = ffcpqt_expect("nonce diversifies", nonce_a != 1009 && nonce_a != nonce_b)
z = ffcpqt_expect("nonce bounded", nonce_a >= 0 && nonce_a <= 4611686018427387903)

nonce_capacity = ffw_default_capacity(2) ## i64
nonce_state_size = ffw_state_size(nonce_capacity) ## i64
direct_state = i64[nonce_state_size]
zero_state = i64[nonce_state_size]
diverse_state = i64[nonce_state_size]
z = ffcpqt_expect("direct seed init", ffw_init_naive_cap(direct_state, 2, nonce_capacity, 1009, 1, 2, 100, 25) == 8)
z = ffcpqt_expect("zero nonce init", ffw_init_naive_cap(zero_state, 2, nonce_capacity, ffcp_campaign_seed(1009, 0), 1, 2, 100, 25) == 8)
z = ffcpqt_expect("nonzero nonce init", ffw_init_naive_cap(diverse_state, 2, nonce_capacity, ffcp_campaign_seed(1009, 7), 1, 2, 100, 25) == 8)
z = ffw_walk(direct_state, 1000) ## i64
z = ffw_walk(zero_state, 1000)
z = ffw_walk(diverse_state, 1000)
same_zero = 1 ## i64
word = 0 ## i64
while word < nonce_state_size
  if direct_state[word] != zero_state[word]
    same_zero = 0
  word += 1
z = ffcpqt_expect("zero nonce trajectory identity", same_zero == 1)
z = ffcpqt_expect("nonzero nonce trajectory differs", diverse_state[8] != direct_state[8])
z = ffcpqt_expect("nonce trajectories remain exact", ffw_verify_current_exact(direct_state, 2) == 1 && ffw_verify_current_exact(diverse_state, 2) == 1)

range_steps = i64[4]
range_out = i64[2]
range_steps[0] = 700
range_steps[1] = 12
range_steps[2] = 900
range_steps[3] = 33
z = ffcpqt_expect("step range return", ffcp_round_step_range(range_steps, 4, range_out) == 900)
z = ffcpqt_expect("step range values", range_out[0] == 12 && range_out[1] == 900)

<< "PASS cpu pool adaptive quota median=" + median.to_s() + " slow_steps=" + slow.to_s() + " wide_steps=" + wide_steps.to_s() + " nonce=" + nonce_a.to_s()
