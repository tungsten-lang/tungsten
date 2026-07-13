# flipfleet_gpu_policy.w -- pure native adaptive GPU portfolio policy.
#
# This module contains no processes, files, clocks, Metal calls, or Python
# runtime.  A native coordinator owns eleven-element i64 arrays and calls this
# policy to fill weights/eligibility, allocate physical lanes, account complete
# epochs and exact candidates, decide when to rebalance, and construct commands
# for the heterogeneous native engines.
#
# Role codes come from flipfleet_profiles:
#   0 rank, 1 density, 2 symmetry, 3 split, 4 break, 5 orbit,
#   6 polarize, 7 compose, 8 novelty, 9 cooperative SIMD, 10 rotating pool.
#
# Every allocation is in 32-lane quanta.  Positive-weight eligible roles get a
# one-quantum diversity floor whenever the budget can cover every such role.
# Zero-weight roles remain off even when otherwise eligible.  If the budget is
# too small, allocation is deterministic best effort and the allocator returns
# zero so the coordinator can report degraded coverage rather than silently
# claiming that all diversity floors are live.

use flipfleet_profiles

-> ffg_role_count() i64
  11

-> ffg_lane_quantum() i64
  32

-> ffg_valid_role(role) (i64) i64
  ok = 0 ## i64
  if role >= 0 && role < 11
    ok = 1
  ok

-> ffg_role_name(role) (i64)
  out = "invalid"
  if ffg_valid_role(role) == 1
    out = ffp_gpu_role_name(role)
  out

# A C3 seed is required for symmetry-preserving, orbit, and polarization lanes.
# Availability of a compiled engine can be applied by the caller by clearing
# the corresponding eligibility slot after this helper returns.
-> ffg_profile_eligible(n, role, has_c3_seed) (i64 i64 i64) i64
  eligible = 0 ## i64
  if ffg_valid_role(role) == 1
    if ffp_gpu_weight(n, role) > 0
      eligible = 1
  if role == 2 || role == 5 || role == 6
    if has_c3_seed == 0
      eligible = 0
  eligible

# `eligible` and `weights` must each have at least eleven i64 slots.
-> ffg_fill_profile(n, has_c3_seed, eligible, weights) (i64 i64 i64[] i64[]) i64
  active = 0 ## i64
  role = 0 ## i64
  while role < 11
    allowed = ffg_profile_eligible(n, role, has_c3_seed) ## i64
    eligible[role] = allowed
    weights[role] = 0
    if allowed == 1
      weights[role] = ffp_gpu_weight(n, role)
      if weights[role] > 0
        active += 1
    role += 1
  active

-> ffg_active_role(eligible, weights, role) (i64[] i64[] i64) i64
  active = 0 ## i64
  if role >= 0 && role < 11
    if eligible[role] != 0 && weights[role] > 0
      active = 1
  active

-> ffg_active_count(eligible, weights) (i64[] i64[]) i64
  count = 0 ## i64
  role = 0 ## i64
  while role < 11
    count += ffg_active_role(eligible, weights, role)
    role += 1
  count

-> ffg_can_cover_floors(total_lanes, eligible, weights) (i64 i64[] i64[]) i64
  can = 0 ## i64
  chunks = total_lanes / 32 ## i64
  if chunks >= ffg_active_count(eligible, weights)
    can = 1
  can

-> ffg_clear_allocation(allocation) (i64[]) i64
  role = 0 ## i64
  while role < 11
    allocation[role] = 0
    role += 1
  0

-> ffg_lane_sum(allocation) (i64[]) i64
  total = 0 ## i64
  role = 0 ## i64
  while role < 11
    total += allocation[role]
    role += 1
  total

-> ffg_allocation_changed(left, right) (i64[] i64[]) i64
  changed = 0 ## i64
  role = 0 ## i64
  while role < 11
    if left[role] != right[role]
      changed = 1
    role += 1
  changed

# Evidence-weighted cold allocation with Hamilton/largest-remainder rounding.
# Returns one when every active role received its floor, zero for deterministic
# best effort when fewer quanta than roles are available.
-> ffg_initial_allocate(total_lanes, eligible, weights, allocation) (i64 i64[] i64[] i64[]) i64
  z = ffg_clear_allocation(allocation) ## i64
  chunks = total_lanes / 32 ## i64
  active = ffg_active_count(eligible, weights) ## i64
  floors_covered = 1 ## i64
  if chunks < active
    floors_covered = 0

  if chunks > 0 && active > 0
    if floors_covered == 0
      # Spend scarce quanta on the largest configured weights.  A role is
      # selected at most once because there is no budget beyond its floor.
      used = 0 ## i64
      while used < chunks
        best_role = 0 - 1 ## i64
        best_weight = 0 - 1 ## i64
        role = 0 ## i64
        while role < 11
          if ffg_active_role(eligible, weights, role) == 1
            if allocation[role] == 0
              if weights[role] > best_weight
                best_weight = weights[role]
                best_role = role
          role += 1
        if best_role >= 0
          allocation[best_role] = 32
        used += 1

    if floors_covered == 1
      role = 0
      total_weight = 0 ## i64
      while role < 11
        if ffg_active_role(eligible, weights, role) == 1
          allocation[role] = 32
          total_weight += weights[role]
        role += 1

      remaining = chunks - active ## i64
      remainders = i64[11]
      picked = i64[11]
      assigned_extra = 0 ## i64
      role = 0
      while role < 11
        remainders[role] = 0
        picked[role] = 0
        if ffg_active_role(eligible, weights, role) == 1
          share_numerator = remaining * weights[role] ## i64
          share = share_numerator / total_weight ## i64
          allocation[role] = allocation[role] + share * 32
          assigned_extra += share
          remainders[role] = share_numerator % total_weight
        role += 1

      left = remaining - assigned_extra ## i64
      while left > 0
        best_role = 0 - 1
        best_remainder = 0 - 1 ## i64
        role = 0
        while role < 11
          if ffg_active_role(eligible, weights, role) == 1
            if picked[role] == 0
              if remainders[role] > best_remainder
                best_remainder = remainders[role]
                best_role = role
          role += 1
        if best_role >= 0
          allocation[best_role] = allocation[best_role] + 32
          picked[best_role] = 1
        left -= 1
  floors_covered

# ---- reward and exposure accounting ------------------------------------------

# Call at the end of each completed adaptive interval.  `lane_epochs` is the
# caller's standardized exposure counter; native FlipFleet uses one occupied
# 32-lane quantum for 100ms.  Roles with no allocation receive no exposure.
# The per-epoch reward accumulator is reset for the next period.
-> ffg_complete_epoch(allocation, eligible, epochs, lane_epochs, epoch_reward_milli) (i64[] i64[] i64[] i64[] i64[]) i64
  added = 0 ## i64
  role = 0 ## i64
  while role < 11
    epoch_reward_milli[role] = 0
    if eligible[role] != 0 && allocation[role] > 0
      chunks = allocation[role] / 32 ## i64
      if chunks < 1
        chunks = 1
      epochs[role] = epochs[role] + 1
      lane_epochs[role] = lane_epochs[role] + chunks
      added += chunks
    role += 1
  added

# Exact-candidate reward, in milli-reward units.  Rank gain dominates; density
# and Pareto novelty are deliberately bounded.  The arrays have eleven slots.
-> ffg_record_candidate(role, best_rank, candidate_rank, current_bits, candidate_bits, pareto_admitted, novelty, reward_milli, epoch_reward_milli, candidates, pareto_admissions, rank_drops, density_improvements) (i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  reward = 0 ## i64
  if ffg_valid_role(role) == 0
    return 0
  candidates[role] = candidates[role] + 1

  rank_gain = best_rank - candidate_rank ## i64
  if rank_gain > 0
    rank_drops[role] = rank_drops[role] + 1
    reward += rank_gain * 10000
  if rank_gain <= 0
    if candidate_rank == best_rank
      bit_gain = current_bits - candidate_bits ## i64
      if bit_gain > 0
        density_improvements[role] = density_improvements[role] + 1
        density_reward = 0 ## i64
        if current_bits > 0
          density_reward = (2000 * bit_gain) / current_bits
        if density_reward > 2000
          density_reward = 2000
        reward += density_reward

  if pareto_admitted != 0
    pareto_admissions[role] = pareto_admissions[role] + 1
    novelty_reward = 0 ## i64
    denominator = candidate_rank * 2 ## i64
    if denominator > 0 && novelty > 0
      novelty_reward = (novelty * 1000) / denominator
    if novelty_reward > 1000
      novelty_reward = 1000
    reward += 1000 + novelty_reward

  reward_milli[role] = reward_milli[role] + reward
  epoch_reward_milli[role] = epoch_reward_milli[role] + reward
  reward

-> ffg_reward_milli_per_lane_epoch(reward_milli, lane_epochs, role) (i64[] i64[] i64) i64
  result = 0 - 1 ## i64
  if ffg_valid_role(role) == 1
    if lane_epochs[role] > 0
      result = reward_milli[role] / lane_epochs[role]
  result

# ---- integer UCB scheduler ----------------------------------------------------

-> ffg_log2_floor(value) (i64) i64
  n = value ## i64
  result = 0 ## i64
  while n >= 2
    n = n / 2
    result += 1
  result

-> ffg_isqrt(value) (i64) i64
  result = 0 ## i64
  if value > 0
    x = value ## i64
    y = (x + 1) / 2 ## i64
    while y < x
      x = y
      y = (x + value / x) / 2
    result = x
  result

# UCB score in milli-reward units.  The coordinator supplies standardized
# exposure pulls (currently one 32-lane/100ms quantum), so generic, C3, SIMD,
# and MITM epochs remain comparable despite different launch shapes.
# log2(total)*0.693 approximates ln(total) without floating point; the bonus
# remains close to sqrt(2 ln(total)/pulls).
-> ffg_role_score_milli(role, eligible, weights, lane_epochs, reward_milli, total_exposure) (i64 i64[] i64[] i64[] i64[] i64) i64
  score = 0 - 1 ## i64
  if ffg_active_role(eligible, weights, role) == 1
    pulls = lane_epochs[role] ## i64
    if pulls <= 0
      score = 1000000000
    if pulls > 0
      mean = reward_milli[role] / pulls ## i64
      total = total_exposure ## i64
      if total < 2
        total = 2
      log2_total = ffg_log2_floor(total) ## i64
      bonus_square = (1386000 * log2_total) / pulls ## i64
      bonus = ffg_isqrt(bonus_square) ## i64
      score = mean + bonus
  score

# Warm adaptive allocation.  Cold roles use the evidence-weighted profile.
# Once every role has exposure, UCB productivity selects each extra quantum;
# score/sqrt(current quanta) gives diminishing returns and prevents a lucky
# role from consuming the whole device.  Returns floor-coverage status.
-> ffg_adaptive_allocate(total_lanes, eligible, weights, lane_epochs, reward_milli, allocation) (i64 i64[] i64[] i64[] i64[] i64[]) i64
  active = ffg_active_count(eligible, weights) ## i64
  chunks = total_lanes / 32 ## i64
  cold = 0 ## i64
  total_exposure = 0 ## i64
  role = 0 ## i64
  while role < 11
    if ffg_active_role(eligible, weights, role) == 1
      if lane_epochs[role] <= 0
        cold = 1
      total_exposure += lane_epochs[role]
    role += 1
  if active == 0
    return ffg_initial_allocate(total_lanes, eligible, weights, allocation)
  if cold == 1 || chunks < active
    return ffg_initial_allocate(total_lanes, eligible, weights, allocation)

  z = ffg_clear_allocation(allocation) ## i64
  role = 0
  while role < 11
    if ffg_active_role(eligible, weights, role) == 1
      allocation[role] = 32
    role += 1

  used = active ## i64
  while used < chunks
    best_role = 0 - 1 ## i64
    best_adjusted = 0 - 1 ## i64
    role = 0
    while role < 11
      if ffg_active_role(eligible, weights, role) == 1
        score = ffg_role_score_milli(role, eligible, weights, lane_epochs, reward_milli, total_exposure) ## i64
        role_chunks = allocation[role] / 32 ## i64
        # score/sqrt(chunks), with two fixed decimal digits.  Taking the root
        # before multiplication avoids score^2 cross-products overflowing in
        # a very long campaign with a large accumulated mean reward.
        root100 = ffg_isqrt(role_chunks * 10000) ## i64
        adjusted = (score * 100) / root100 ## i64
        if best_role < 0
          best_role = role
          best_adjusted = adjusted
        if adjusted > best_adjusted
          best_role = role
          best_adjusted = adjusted
      role += 1
    if best_role >= 0
      allocation[best_role] = allocation[best_role] + 32
    used += 1
  1

# Reserve a bounded role-10 kernel-pool budget, then allocate the remainder
# among continuously active roles. The caller computes `pool_lanes` from the
# pool policy. Temporarily clearing role 10 avoids counting it twice while
# retaining the established eleven-slot telemetry ABI and TUI row.
-> ffg_initial_allocate_pool(total_lanes, pool_lanes, eligible, weights, allocation) (i64 i64 i64[] i64[] i64[]) i64
  reserve = 0 ## i64
  old_eligible = eligible[10] ## i64
  old_weight = weights[10] ## i64
  if old_eligible != 0 && old_weight > 0
    reserve = pool_lanes
  if reserve < 0
    reserve = 0
  if reserve > total_lanes
    reserve = total_lanes
  eligible[10] = 0
  weights[10] = 0
  covered = ffg_initial_allocate(total_lanes - reserve, eligible, weights, allocation) ## i64
  eligible[10] = old_eligible
  weights[10] = old_weight
  allocation[10] = reserve
  covered

-> ffg_adaptive_allocate_pool(total_lanes, pool_lanes, eligible, weights, lane_epochs, reward_milli, allocation) (i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  reserve = 0 ## i64
  old_eligible = eligible[10] ## i64
  old_weight = weights[10] ## i64
  if old_eligible != 0 && old_weight > 0
    reserve = pool_lanes
  if reserve < 0
    reserve = 0
  if reserve > total_lanes
    reserve = total_lanes
  eligible[10] = 0
  weights[10] = 0
  covered = ffg_adaptive_allocate(total_lanes - reserve, eligible, weights, lane_epochs, reward_milli, allocation) ## i64
  eligible[10] = old_eligible
  weights[10] = old_weight
  allocation[10] = reserve
  covered

-> ffg_rebalance_due(last_rebalance_ms, now_ms, interval_ms) (i64 i64 i64) i64
  due = 0 ## i64
  if last_rebalance_ms < 0
    due = 1
  if interval_ms <= 0
    due = 1
  if last_rebalance_ms >= 0
    if now_ms - last_rebalance_ms >= interval_ms
      due = 1
  due

# Fill `proposed`.  Return 0 when not due, 1 when due but unchanged, 2 when due
# and changed, or -1 when due but the lane budget cannot cover all floors.
-> ffg_maybe_rebalance(last_rebalance_ms, now_ms, interval_ms, total_lanes, eligible, weights, lane_epochs, reward_milli, current, proposed) (i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if ffg_rebalance_due(last_rebalance_ms, now_ms, interval_ms) == 0
    role = 0 ## i64
    while role < 11
      proposed[role] = current[role]
      role += 1
    return 0
  covered = ffg_adaptive_allocate(total_lanes, eligible, weights, lane_epochs, reward_milli, proposed) ## i64
  if covered == 0
    return 0 - 1
  if ffg_allocation_changed(current, proposed) == 1
    return 2
  1

# ---- role engine and launch profiles -----------------------------------------

# Engine codes: 0 generic cal2zone, 1 C3-preserving, 2 cooperative SIMD,
# 3 rotating experimental pool, -1 invalid.
-> ffg_engine_kind(role) (i64) i64
  kind = 0 - 1 ## i64
  if ffg_valid_role(role) == 1
    kind = 0
  if role == 2
    kind = 1
  if role == 9
    kind = 2
  if role == 10
    kind = 3
  kind

-> ffg_engine_name(role) (i64)
  kind = ffg_engine_kind(role) ## i64
  out = "invalid"
  if kind == 0
    out = "cal2zone"
  if kind == 1
    out = "c3-preserving"
  if kind == 2
    out = "cooperative-simd"
  if kind == 3
    out = "kernel-pool"
  out

-> ffg_cal2zone_workq(role) (i64) i64
  vals = i64[11]
  vals[0] = 220000
  vals[1] = 250000
  vals[2] = 0
  vals[3] = 80000
  vals[4] = 90000
  vals[5] = 100000
  vals[6] = 100000
  vals[7] = 90000
  vals[8] = 120000
  vals[9] = 0
  vals[10] = 0
  vals[role]

-> ffg_cal2zone_wanderq(role) (i64) i64
  vals = i64[11]
  vals[0] = 90000
  vals[1] = 100000
  vals[2] = 0
  vals[3] = 25000
  vals[4] = 30000
  vals[5] = 35000
  vals[6] = 35000
  vals[7] = 30000
  vals[8] = 40000
  vals[9] = 0
  vals[10] = 0
  vals[role]

-> ffg_cal2zone_wthr(role) (i64) i64
  vals = i64[11]
  vals[0] = 9
  vals[1] = 9
  vals[2] = 0
  vals[3] = 4
  vals[4] = 4
  vals[5] = 5
  vals[6] = 5
  vals[7] = 4
  vals[8] = 6
  vals[9] = 0
  vals[10] = 0
  vals[role]

# -1 means the split engine should enumerate all legal +1 splits.
-> ffg_cal2zone_escapes(role) (i64) i64
  escapes = 1 ## i64
  if role == 3
    escapes = 0 - 1
  escapes

-> ffg_symmetry_steps() i64
  2000

-> ffg_symmetry_dispatches() i64
  1

-> ffg_symmetry_band() i64
  15

-> ffg_symmetry_plus_period() i64
  200

-> ffg_simd_steps() i64
  20000

-> ffg_simd_dispatches() i64
  1

-> ffg_simd_margin() i64
  4

# 0 auto, 1 scan, 2 hash.  Measured tensor defaults: scan for 5x5, hash for
# 6x6; the safe fallback uses hash for >=6 and scan below it.
-> ffg_simd_mode(n) (i64) i64
  mode = 1 ## i64
  if n >= 6
    mode = 2
  mode

-> ffg_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

# Generic cal2zone positional ABI:
# bin seed out n n n x 0 steps reseed margin workq wanderq wthr lanes live
# escapes rounds.  A negative role escape marker means "use the caller's
# exact split portfolio", but the relay ABI itself is numeric (`String#to_i`),
# so never pass the old literal `all`.
-> ffg_cal2zone_command(binary, seed_path, output_path, live_path, n, role, steps, lanes, split_portfolio, epoch_rounds) (String String String String i64 i64 i64 i64 i64 i64)
  if lanes < 1
    return ""
  escapes = ffg_cal2zone_escapes(role) ## i64
  if escapes < 0
    escapes = split_portfolio
  if escapes < 1
    escapes = 1
  if escapes > lanes
    escapes = lanes
  rounds = epoch_rounds ## i64
  if rounds < 1
    rounds = 1
  ffg_shell_quote(binary) + " " + ffg_shell_quote(seed_path) + " " + ffg_shell_quote(output_path) + " " + n.to_s() + " " + n.to_s() + " " + n.to_s() + " x 0 " + steps.to_s() + " " + ffp_gpu_reseed(role).to_s() + " " + ffp_gpu_margin(role).to_s() + " " + ffg_cal2zone_workq(role).to_s() + " " + ffg_cal2zone_wanderq(role).to_s() + " " + ffg_cal2zone_wthr(role).to_s() + " " + lanes.to_s() + " " + ffg_shell_quote(live_path) + " " + escapes.to_s() + " " + rounds.to_s()

# Dedicated C3 relay ABI: bin seed out walkers steps dispatches band plus_period
-> ffg_symmetry_command(binary, seed_path, output_path, lanes) (String String String i64)
  ffg_shell_quote(binary) + " " + ffg_shell_quote(seed_path) + " " + ffg_shell_quote(output_path) + " " + lanes.to_s() + " " + ffg_symmetry_steps().to_s() + " " + ffg_symmetry_dispatches().to_s() + " " + ffg_symmetry_band().to_s() + " " + ffg_symmetry_plus_period().to_s()

# Cooperative SIMD ABI: bin seed out groups steps dispatches margin mode.
-> ffg_simd_command(binary, seed_path, output_path, lanes, n) (String String String i64 i64)
  groups = lanes / 32 ## i64
  if groups < 1
    groups = 1
  ffg_shell_quote(binary) + " " + ffg_shell_quote(seed_path) + " " + ffg_shell_quote(output_path) + " " + groups.to_s() + " " + ffg_simd_steps().to_s() + " " + ffg_simd_dispatches().to_s() + " " + ffg_simd_margin().to_s() + " " + ffg_simd_mode(n).to_s()

# Native positional MITM ABI: bin seed out n subsets pool nearby offset.
-> ffg_mitm_command(binary, seed_path, output_path, n, subsets, pool, nearby, offset) (String String String i64 i64 i64 i64 i64)
  ffg_shell_quote(binary) + " " + ffg_shell_quote(seed_path) + " " + ffg_shell_quote(output_path) + " " + n.to_s() + " " + subsets.to_s() + " " + pool.to_s() + " " + nearby.to_s() + " " + offset.to_s()

-> ffg_mitm_nearby(launch_number) (i64) i64
  number = launch_number ## i64
  if number < 1
    number = 1
  1 + ((number - 1) % 3)

-> ffg_mitm_plan(lanes, gpu_steps, max_pool, target_subsets, plan) (i64 i64 i64 i64 i64[]) i64
  steps = gpu_steps ## i64
  if steps > 4096
    steps = 4096
  if steps < 1
    steps = 1
  logical_threads = lanes * steps ## i64
  pool_cap = max_pool ## i64
  if pool_cap < 4
    pool_cap = 4
  target = target_subsets ## i64
  if target < 1
    target = 1

  subsets = 1 ## i64
  pool = 4 ## i64
  if logical_threads >= 16
    subsets = logical_threads / 16
    if subsets > target
      subsets = target
    if subsets < 1
      subsets = 1
    pool = ffg_isqrt(logical_threads / subsets)
    if pool > pool_cap
      pool = pool_cap
    if pool < 4
      pool = 4
    desired = subsets ## i64
    if desired < target
      desired = target
    max_subsets = logical_threads / (pool * pool) ## i64
    if max_subsets < 1
      max_subsets = 1
    subsets = desired
    if subsets > max_subsets
      subsets = max_subsets

  plan[0] = logical_threads
  plan[1] = subsets
  plan[2] = pool
  plan[3] = subsets * pool * pool
  plan[3]
