# Pure policy helpers for Metaflip's 7x7 campaign and rectangular subfleet.
#
# Keeping these decisions outside the coordinator makes the lane budget,
# backoff, contextual accounting, TUI cells, and retained rank-250 shoulder
# independently testable without starting a campaign.

use ../kernels/pool
use ../tui
use banks
use archive
use map_elites

# Independently admit one already exact-gated partial-automorphism endpoint to
# the global max-min frontier archive and MAP-Elites.  These are complementary
# policies: archive rejection must not suppress a novel MAP niche.  `stats`
# receives the raw archive result (0/1) and MAP result (0/1/2); the return mask
# uses bit 0 for archive change and bit 1 for any MAP change.
-> ff7_partial_auto_admit(archive_states, archive_capacity, archive_min_distance, archive_counters, map_states, map_keys, map_uses, map_sources, map_capacity, candidate, frontier_rank, n, state_size, source, seed, stats) i64
  if stats.size() < 2
    return 0
  stats[0] = 0
  stats[1] = 0
  if n != 7 || candidate == nil || ffw_best_rank(candidate) != frontier_rank
    return 0
  archive_changed = ffn_archive_add_copy(archive_states, candidate, archive_capacity, archive_min_distance, archive_counters, state_size, seed) ## i64
  # Deliberately unconditional on archive_changed.
  map_changed = ffme_add_copy(map_states, map_keys, map_uses, map_sources, candidate, frontier_rank, n, map_capacity, source, state_size, seed + 1009) ## i64
  stats[0] = archive_changed
  stats[1] = map_changed
  result = archive_changed ## i64
  if map_changed > 0
    result += 2
  result

# Malformed canonical checkpoints are renamed out of the way before the
# coordinator atomically reseeds the canonical path.  The run tag makes the
# preserved bytes immutable and diagnostic while the stable canonical name
# remains restart-durable.
-> ff7_corrupt_checkpoint_path(path, run_tag) (String String)
  path + ".corrupt." + run_tag

-> ff7_quarantine_corrupt_checkpoint(path, run_tag) (String String) i64
  target = ff7_corrupt_checkpoint_path(path, run_tag)
  moved = ccall("__w_rename", path, target)
  if moved
    return 1
  0

# Reserve one sixth of role 10's existing pool budget for each ready 7x7
# rectangular component.  At the default 1,536-lane pool this is 256+256;
# the three rotating kernel families water-fill the remaining 1,024 lanes.
-> ff7_rect_pool_allocation(pool_budget, epoch, ready, exposure, rewards, allocation) (i64 i64 i64[] i64[] i64[] i64[]) i64
  slot = 0 ## i64
  while slot < allocation.size()
    allocation[slot] = 0
    slot += 1
  if pool_budget < 32
    return 0
  nominal = (pool_budget / 6 / 32) * 32 ## i64
  if nominal < 32
    nominal = 32
  ready_count = 0 ## i64
  component = 0 ## i64
  while component < 2
    if component < ready.size() && ready[component] != 0
      ready_count += 1
    component += 1
  target = nominal * ready_count ## i64
  if target > pool_budget
    target = (pool_budget / 32) * 32
  remaining = target ## i64
  offset = 0 ## i64
  used = 0 ## i64
  # Every ready component gets one SIMDgroup before evidence is considered.
  while offset < 2
    component = (epoch + offset) % 2 ## i64
    if component < ready.size() && component < allocation.size()
      if ready[component] != 0 && remaining >= 32
        allocation[component] = 32
        remaining -= 32
        used += 32
    offset += 1
  if remaining >= 32 && ready_count > 0
    score0 = 0 ## i64
    score1 = 0 ## i64
    if exposure.size() > 0 && rewards.size() > 0 && exposure[0] > 0
      score0 = rewards[0] * 1000 / exposure[0]
    if exposure.size() > 1 && rewards.size() > 1 && exposure[1] > 0
      score1 = rewards[1] * 1000 / exposure[1]
    extra_chunks = remaining / 32 ## i64
    extra0 = 0 ## i64
    if ready_count == 1
      if ready[0] != 0
        extra0 = extra_chunks
    if ready_count == 2
      total_score = score0 + score1 ## i64
      if total_score > 0
        extra0 = extra_chunks * score0 / total_score
      if total_score == 0
        extra0 = extra_chunks / 2
        if (extra_chunks % 2) != 0 && (epoch % 2) == 0
          extra0 += 1
    extra1 = extra_chunks - extra0 ## i64
    if ready[0] == 0
      extra1 = extra_chunks
      extra0 = 0
    if ready[1] == 0
      extra0 = extra_chunks
      extra1 = 0
    allocation[0] = allocation[0] + extra0 * 32
    allocation[1] = allocation[1] + extra1 * 32
    used += extra_chunks * 32
  used

# Water-fill the selected generic pool children from the explicit remainder.
# Mode caps can leave part of the requested budget unused; callers return that
# residual to continuous roles at the next clean adaptive boundary.
-> ff7_allocate_pool_remainder_for_tensor(n, total_lanes, budget, selected, count, allocation) (i64 i64 i64 i64[] i64 i64[]) i64
  slot = 0 ## i64
  while slot < allocation.size()
    allocation[slot] = 0
    slot += 1
  chunks = budget / 32 ## i64
  active = count ## i64
  if active > ffkp_parallel_slots()
    active = ffkp_parallel_slots()
  if active > selected.size()
    active = selected.size()
  if active > allocation.size()
    active = allocation.size()
  if active > chunks
    active = chunks
  if active < 1
    return 0
  slot = 0
  while slot < active
    allocation[slot] = 32
    slot += 1
  used = active ## i64
  while used < chunks
    best_slot = 0 - 1 ## i64
    least_lanes = 0 ## i64
    slot = 0
    while slot < active
      cap = ffkp_mode_lane_budget_for_tensor(n, total_lanes, selected[slot]) ## i64
      if allocation[slot] < cap
        if best_slot < 0 || allocation[slot] < least_lanes
          best_slot = slot
          least_lanes = allocation[slot]
      slot += 1
    if best_slot < 0
      return used * 32
    allocation[best_slot] = allocation[best_slot] + 32
    used += 1
  used * 32

-> ff7_allocate_pool_remainder(total_lanes, budget, selected, count, allocation) (i64 i64 i64[] i64 i64[]) i64
  ff7_allocate_pool_remainder_for_tensor(7, total_lanes, budget, selected, count, allocation)

# Effective readiness is physical readiness intersected with per-component
# exponential backoff.  A failed child therefore returns its reserve to the
# rest of role 10 until its retry round, without disabling its sibling.
-> ff7_fill_rect_sched_ready(round, ready, retry_round, output) (i64 i64[] i64[] i64[]) i64
  count = 0 ## i64
  component = 0 ## i64
  while component < 2
    output[component] = 0
    if component < ready.size() && component < retry_round.size()
      if ready[component] != 0 && round >= retry_round[component]
        output[component] = 1
        count += 1
    component += 1
  count

-> ff7_composition_due(dirty, round, retry_round) (i64 i64 i64) i64
  due = 0 ## i64
  if dirty != 0 && round >= retry_round
    due = 1
  due

# Dedicated pool children occupy physical slots 10..12 and can launch at
# different rank debts; rectangular evidence is deliberately credited to debt
# zero.  Aggregate all four debt contexts for logical role 10 so adaptive UCB
# cannot accidentally ignore two children and both component subfleets.
-> ff7_fill_contextual_evidence(n, launch_debt, transition_exposure, transition_rewards, contextual_exposure, contextual_rewards) (i64 i64[] i64[] i64[] i64[] i64[]) i64
  context_count = ffkp_context_count() ## i64
  role = 0 ## i64
  while role < 11
    contextual_exposure[role] = 0
    contextual_rewards[role] = 0
    if role == 10
      debt = 0 ## i64
      while debt < 4
        context = ffkp_context(n, debt) ## i64
        index = role * context_count + context ## i64
        contextual_exposure[role] = contextual_exposure[role] + transition_exposure[index]
        contextual_rewards[role] = contextual_rewards[role] + transition_rewards[index]
        debt += 1
    if role != 10
      context = ffkp_context(n, launch_debt[role]) ## i64
      index = role * context_count + context ## i64
      contextual_exposure[role] = transition_exposure[index]
      contextual_rewards[role] = transition_rewards[index]
    role += 1
  1

# Fixed-column component label.  ff_tui_gpu_pool_cell applies the active/dim
# marker and final clipping; these fields stay put as counters change width.
-> ff7_rect_pool_label(name, lanes, rank, archives, drops, reward, failures, ready, active, round, retry_round, composition_failures) (String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
  rank_text = "r?"
  if rank > 0
    rank_text = "r" + rank.to_s()
  state = "idle  "
  if active != 0 && ready != 0
    state = "active"
  if ready == 0
    state = "off   "
  if ready != 0 && active == 0 && round < retry_round
    state = "retry "
  name + " " + ff_tui_pad_left(lanes.to_s() + "l", 6) + " " + ff_tui_pad_left(rank_text, 4) + " " + ff_tui_pad_left("A" + archives.to_s(), 4) + " " + ff_tui_pad_left("d" + drops.to_s(), 4) + " " + ff_tui_compact_fixed(reward, 6) + " " + state + " " + ff_tui_pad_left("fail" + failures.to_s(), 7) + " " + ff_tui_pad_left("cfail" + composition_failures.to_s(), 7)

# The rank-248 block construction is close in rank but far in term space from
# the previous exact rank-250 frontier.  Retain that frontier as a true +2
# shoulder whenever 248 is the leader.  Leave this signature inferred: near2
# is an Array of state arrays, not a flat i64[] buffer.
-> ff7_add_known_7x7_shoulder(root, best, n, capacity, state_size, dslack, cycles, workq, wanderq, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, signature_quota, near_counters)
  if n != 7 || ffw_best_rank(best) != 248
    return 0
  shoulder_path = root + "/seeds/gf2/matmul_7x7_rank250_d2966_gf2.txt"
  shoulder = i64[state_size]
  shoulder_rank = ffw_load_scheme_cap(shoulder, shoulder_path, n, capacity, 39007, dslack, cycles, workq, wanderq) ## i64
  if shoulder_rank != 250
    return 0
  ffbp_near_add(near2, near2_signatures, near2_uses, near2_successes, shoulder, near2_capacity, signature_quota, 4, near_counters)

# The rank-247 outer-isotropy composition makes all four independently exact
# rank-248 presentations true +1 shoulders.  Keep them out of the same-rank
# frontier list and admit them through ordinary structural quotas/max-min
# replacement so the CPU/GPU restart banks retain their distinct doors.
-> ff7_add_known_7x7_rank247_shoulders(root, best, n, capacity, state_size, dslack, cycles, workq, wanderq, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, signature_quota, near_counters)
  if n != 7 || ffw_best_rank(best) != 247
    return 0
  names = ["matmul_7x7_rank248_d2952_sedoglavic_gf2.txt",
           "matmul_7x7_rank248_d2958_sedoglavic_gf2.txt",
           "matmul_7x7_rank248_d2967_leaf_canonical_gf2.txt",
           "matmul_7x7_rank248_d3015_connectivity_sedoglavic_gf2.txt"]
  base = root + "/seeds/gf2/"
  admitted = 0 ## i64
  i = 0 ## i64
  while i < names.size()
    shoulder = i64[state_size]
    path = base + names[i]
    rank = ffw_load_scheme_cap(shoulder, path, n, capacity, 39101 + i * 17, dslack, cycles, workq, wanderq) ## i64
    if rank == 248 && ffw_verify_best_exact(shoulder, n) == 1
      if ffbp_near_add(near1, near1_signatures, near1_uses, near1_successes, shoulder, near1_capacity, signature_quota, 4, near_counters) == 1
        admitted += 1
    i += 1
  admitted
