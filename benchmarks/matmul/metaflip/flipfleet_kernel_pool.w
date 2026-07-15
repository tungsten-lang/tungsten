# Rotating experimental GPU-kernel pool policy for native FlipFleet.
#
# The proven rank/density/C3/escape/SIMD roles keep dedicated allocations.
# Role 10 reserves a bounded fraction of the device and rotates these modes:
#   0 projected-defect R-1 search
#   1 exact 5->4 MITM surgery
#   2 exact 6->5 XOR surgery
#   3 exact 7->6 XOR surgery
#   4 lifted subspace identities followed by an ordinary GPU walk
#   5 substitution/flattening lower-bound scout
#   6 XOR-SAT cube scorer
#   7 fixed-cube symmetry break
#   8 orbit split
#   9 cubic polarization
#  10 beam-searched mixed escape recipes
#  11 live primitive five/six-term zero-circuit mining
#  12 distant-parent differential surgery (one CPU child maximum)
#  13 exact 8->7 staged XOR surgery
#  14 exact 9->8 staged XOR surgery
#  15 complete three-term factor-span refactoring
#  16 complete four-term factor-span refactoring
#  17 exact q=2 low-rank shear with correction absorption
#  18 support-clustered frozen-fringe 16->15 SAT (one CPU child, 4x4)
#  19 whole-frontier one-axis kernel shear (one CPU child, 5x5)
#
# One worker is selected from each complementary family.  Within a family,
# every fourth launch is strict rotation and the others use contextual integer
# UCB.  This prevents a noisy early reward from starving either a kernel or an
# entire approach family while still learning tensor/rank-debt niches.

use metaflip_worker
use flipfleet_escape
use flipfleet_beam_recipes
use flipfleet_gpu_policy
use flipfleet_projective_circuit5

-> ffkp_mode_count() i64
  20

# Pool role 10 is one aggregate accounting role, but it may keep one child
# from each of three complementary kernel families in flight.
-> ffkp_group_count() i64
  3

-> ffkp_parallel_slots() i64
  ffkp_group_count()

# 0: constraint and lower-bound scouts; 1: exact local surgery; 2: algebraic
# escape construction followed by an ordinary GPU walk.
-> ffkp_mode_group(mode) (i64) i64
  if mode == 0 || mode == 5 || mode == 6 || mode == 18
    return 0
  if mode == 1 || mode == 2 || mode == 3 || mode == 12 || mode == 13 || mode == 14 || mode == 15 || mode == 16 || mode == 17 || mode == 19
    return 1
  if mode == 4 || mode == 7 || mode == 8 || mode == 9 || mode == 10 || mode == 11
    return 2
  0 - 1

-> ffkp_context_count() i64
  20

-> ffkp_mode_name(mode) (i64)
  if mode == 0
    return "defect-rminus1"
  if mode == 1
    return "mitm-5to4"
  if mode == 2
    return "xor-6to5"
  if mode == 3
    return "xor-7to6"
  if mode == 4
    return "lifted-identity"
  if mode == 5
    return "substitution-lb"
  if mode == 6
    return "xor-sat-cubes"
  if mode == 7
    return "fixed-cube-break"
  if mode == 8
    return "orbit-split"
  if mode == 9
    return "polarization"
  if mode == 10
    return "beam-recipes"
  if mode == 11
    return "primitive-5plus"
  if mode == 12
    return "parent-diff"
  if mode == 13
    return "xor-8to7"
  if mode == 14
    return "xor-9to8"
  if mode == 15
    return "span-refactor-3"
  if mode == 16
    return "span-refactor-4"
  if mode == 17
    return "low-rank-shear"
  if mode == 18
    return "frozen-fringe-sat"
  if mode == 19
    return "global-kernel-shear"
  "invalid"

-> ffkp_mode_kind(mode) (i64) i64
  # 0 constraint scout, 1 old MITM, 2 generalized XOR/circuit,
  # 3 generic cal2zone, 4 bounded single-CPU differential worker,
  # 5 complete local factor-span refactor with a Metal exact-signature join,
  # 6 exact low-rank shear absorption with a regular Metal tuple scan,
  # 7 one bounded CPU frozen-fringe SAT child,
  # 8 one bounded CPU whole-frontier kernel-shear child.
  if mode == 1
    return 1
  if mode == 2 || mode == 3 || mode == 11 || mode == 13 || mode == 14
    return 2
  if mode == 12
    return 4
  if mode == 15 || mode == 16
    return 5
  if mode == 17
    return 6
  if mode == 18
    return 7
  if mode == 19
    return 8
  if mode == 4 || mode == 7 || mode == 8 || mode == 9 || mode == 10
    return 3
  0

-> ffkp_mode_eligible(mode, n, rank) (i64 i64 i64) i64
  ok = 0 ## i64
  if mode >= 0 && mode < ffkp_mode_count() && n >= 3 && n <= 7
    ok = 1
  if mode == 1 && rank < 5
    ok = 0
  if mode == 2 && rank < 6
    ok = 0
  if mode == 3 && rank < 7
    ok = 0
  if mode == 11 && rank < 5
    ok = 0
  if mode == 12 && rank < 5
    ok = 0
  if mode == 13 && rank < 8
    ok = 0
  if mode == 14 && rank < 9
    ok = 0
  if mode == 15 && rank < 3
    ok = 0
  if mode == 16 && rank < 4
    ok = 0
  # Real full-tensor evidence exists at 5x5. Keep 4x4 off as a diagnostic
  # miss, while 6x6/7x7 retain bounded exploratory coverage.
  if mode == 17 && (n < 5 || n > 7 || rank < 3)
    ok = 0
  # The complete 16->15 Brent query is specific to a 4x4 fringe.  Larger
  # tensors need a different decomposition of the SAT window before they can
  # enter this bounded child.
  if mode == 18 && (n != 4 || rank < 16)
    ok = 0
  # Full-frontier evidence is specific and recurring on 5x5 (8/64 exact
  # beyond-one-flip endpoints), while 4x4, 6x6, and 7x7 scans were negative.
  if mode == 19 && (n != 5 || rank < 3)
    ok = 0
  ok

-> ffkp_context(n, rank_debt) (i64 i64) i64
  tensor = n - 3 ## i64
  if tensor < 0
    tensor = 0
  if tensor > 4
    tensor = 4
  debt = rank_debt ## i64
  if debt < 0
    debt = 0
  if debt > 3
    debt = 3
  tensor * 4 + debt

# Three eighths of configured GPU lanes, in 32-lane quanta, capped at 1536.
# Four former always-on algebraic escape roles now rotate here, so this is the
# same broad portfolio without paying four permanent diversity floors.  Small
# devices still give the pool one complete SIMDgroup.
-> ffkp_lane_budget(total_lanes) (i64) i64
  chunks = total_lanes / 32 ## i64
  if chunks < 1
    return 0
  pool_chunks = (chunks * 3) / 8 ## i64
  if pool_chunks < 1
    pool_chunks = 1
  if pool_chunks > 48
    pool_chunks = 48
  pool_chunks * 32

# Host-heavy joins saturate before the persistent/scalable kernels.  Return
# their unused budget to the six continuously active roles for this epoch.
-> ffkp_mode_lane_budget(total_lanes, mode) (i64 i64) i64
  budget = ffkp_lane_budget(total_lanes) ## i64
  cap = 1536 ## i64
  if mode == 1
    cap = 512
  if mode == 2 || mode == 3
    cap = 256
  if mode == 11
    cap = 256
  # Parent-diff is one bounded CPU subprocess.  A single quantum reserves its
  # family slot without pretending that extra GPU width would help it.
  if mode == 12
    cap = 32
  # O(pool^4) tuple enumeration is regular but intentionally narrow.
  if mode == 13 || mode == 14
    cap = 128
  # Three-span neighborhoods are small enough to batch. Four-span joins have
  # up to 3,375 terms and 5,693,625 pairs: charge four SIMDgroups for their
  # device pressure, while the launcher still forces one neighborhood so the
  # large exact pair table is never multiplied by this logical lane reserve.
  if mode == 15
    cap = 256
  if mode == 16
    cap = 128
  if mode == 17
    cap = 256
  if mode == 18
    cap = 32
  if mode == 19
    cap = 32
  if budget > cap
    budget = cap
  budget

# The completed 4x4 campaign gave the constraint family 6,731 launches without
# an exact candidate (substitution reached only contraction bound 16), while
# exact surgery returned frequent exact local hits and generic escape returned
# 4,064 exact schemes plus all six nominal rank-46 near misses.  Keep a four-
# SIMDgroup diagnostic floor for constraint/lower-bound diversity, but cap its
# excess width so water filling sends the remainder to surgery and escape.
-> ffkp_mode_lane_budget_for_tensor(n, total_lanes, mode) (i64 i64 i64) i64
  budget = ffkp_mode_lane_budget(total_lanes, mode) ## i64
  if n == 4 && ffkp_mode_group(mode) == 0 && budget > 128
    budget = 128
  # 5x5 produced a verified non-one-flip absorbed shear after only 504 source
  # pairs.  Larger tensors remain enabled but use half the logical reserve
  # until their tensor-local UCB reward demonstrates the same value.
  if mode == 17 && n >= 6 && budget > 128
    budget = 128
  budget

# Divide the aggregate pool reserve among the selected child modes.  Every
# live child first receives one complete SIMDgroup; remaining groups are
# water-filled toward the least-provisioned child while respecting the
# empirical MITM/XOR saturation caps above.  The return value is the amount
# actually reserved.  When every selected mode saturates, the caller can hand
# the unused part of ffkp_lane_budget() back to the continuous GPU roles.
-> ffkp_allocate_selected_lanes_for_tensor(n, total_lanes, selected, count, allocation) (i64 i64 i64[] i64 i64[]) i64
  slot = 0 ## i64
  while slot < allocation.size()
    allocation[slot] = 0
    slot += 1

  chunks = ffkp_lane_budget(total_lanes) / 32 ## i64
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

-> ffkp_allocate_selected_lanes(total_lanes, selected, count, allocation) (i64 i64[] i64 i64[]) i64
  ffkp_allocate_selected_lanes_for_tensor(0, total_lanes, selected, count, allocation)

-> ffkp_index(mode, context) (i64 i64) i64
  mode * ffkp_context_count() + context

-> ffkp_total_pulls(pulls, context) (i64[] i64) i64
  total = 0 ## i64
  mode = 0 ## i64
  while mode < ffkp_mode_count()
    total += pulls[ffkp_index(mode, context)]
    mode += 1
  total

-> ffkp_next_rotating(last_mode, n, rank) (i64 i64 i64) i64
  offset = 1 ## i64
  while offset <= ffkp_mode_count()
    candidate = (last_mode + offset) % ffkp_mode_count() ## i64
    if ffkp_mode_eligible(candidate, n, rank) == 1
      return candidate
    offset += 1
  0

-> ffkp_next_rotating_ready(last_mode, n, rank, ready) (i64 i64 i64 i64[]) i64
  offset = 1 ## i64
  while offset <= ffkp_mode_count()
    candidate = (last_mode + offset) % ffkp_mode_count() ## i64
    if ffkp_mode_eligible(candidate, n, rank) == 1 && ready[candidate] != 0
      return candidate
    offset += 1
  0 - 1

-> ffkp_select_mode(epoch, last_mode, n, rank, rank_debt, pulls, rewards) (i64 i64 i64 i64 i64 i64[] i64[]) i64
  ready = i64[ffkp_mode_count()]
  i = 0 ## i64
  while i < ffkp_mode_count()
    ready[i] = 1
    i += 1
  ffkp_select_mode_ready(epoch, last_mode, n, rank, rank_debt, ready, pulls, rewards)

-> ffkp_select_mode_ready(epoch, last_mode, n, rank, rank_debt, ready, pulls, rewards) (i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  context = ffkp_context(n, rank_debt) ## i64
  # Cold-start every eligible mode, then retain a hard 25% rotation cadence.
  start = epoch % ffkp_mode_count() ## i64
  offset = 0 ## i64
  while offset < ffkp_mode_count()
    candidate = (start + offset) % ffkp_mode_count() ## i64
    index = ffkp_index(candidate, context) ## i64
    if ffkp_mode_eligible(candidate, n, rank) == 1 && ready[candidate] != 0 && pulls[index] == 0
      return candidate
    offset += 1
  if (epoch % 4) == 0
    return ffkp_next_rotating_ready(last_mode, n, rank, ready)

  total = ffkp_total_pulls(pulls, context) ## i64
  if total < 2
    total = 2
  best = ffkp_next_rotating_ready(last_mode, n, rank, ready) ## i64
  if best < 0
    return 0 - 1
  best_score = 0 - 1 ## i64
  mode = 0 ## i64
  while mode < ffkp_mode_count()
    if ffkp_mode_eligible(mode, n, rank) == 1 && ready[mode] != 0
      index = ffkp_index(mode, context) ## i64
      count = pulls[index] ## i64
      score = 1000000000 ## i64
      if count > 0
        mean = rewards[index] / count ## i64
        bonus_square = (1386000 * ffg_log2_floor(total)) / count ## i64
        score = mean + ffg_isqrt(bonus_square)
      if score > best_score
        best = mode
        best_score = score
    mode += 1
  best

# Select one mode from exactly one kernel family.  This is also the refill
# primitive for asynchronous pool slots: a short constraint or escape child
# can relaunch while a host-heavy surgery child remains in flight.  The
# group's private cursor retains scalar cold-start, forced-rotation, and UCB
# semantics without allowing another family to occupy its slot.
-> ffkp_select_group_mode_ready(epoch, group, n, rank, rank_debt, ready, last_modes, pulls, rewards) (i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if group < 0 || group >= ffkp_group_count()
    return 0 - 1
  scratch_ready = i64[ffkp_mode_count()]
  mode = 0 ## i64
  while mode < ffkp_mode_count()
    scratch_ready[mode] = 0
    if ffkp_mode_group(mode) == group
      scratch_ready[mode] = ready[mode]
    mode += 1
  cursor = 0 - 1 ## i64
  if group < last_modes.size()
    cursor = last_modes[group]
  ffkp_select_mode_ready(epoch, cursor, n, rank, rank_debt, scratch_ready, pulls, rewards)

# Select one bounded batch containing at most one child from each complementary
# kernel family.  `epoch` is the batch epoch, so each family's scalar policy
# retains its own cold coverage, one-in-four rotation, and contextual UCB
# cadence.  Group order rotates to avoid giving the water-fill tie break to the
# same family every batch.  The caller owns `last_modes[group]` and updates it
# only after that group's selected child launches successfully.
-> ffkp_select_group_modes_ready(epoch, n, rank, rank_debt, total_lanes, ready, last_modes, pulls, rewards, selected) (i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  slot = 0 ## i64
  while slot < selected.size()
    selected[slot] = 0 - 1
    slot += 1

  limit = ffkp_parallel_slots() ## i64
  if limit > selected.size()
    limit = selected.size()
  pool_chunks = ffkp_lane_budget(total_lanes) / 32 ## i64
  if limit > pool_chunks
    limit = pool_chunks

  start_group = epoch % ffkp_group_count() ## i64
  group_offset = 0 ## i64
  count = 0 ## i64
  while group_offset < ffkp_group_count() && count < limit
    group = (start_group + group_offset) % ffkp_group_count() ## i64
    chosen = ffkp_select_group_mode_ready(epoch, group, n, rank, rank_debt, ready, last_modes, pulls, rewards) ## i64
    if chosen >= 0
      selected[count] = chosen
      count += 1
    group_offset += 1
  count

-> ffkp_record_launch(mode, n, rank_debt, lane_quanta, pulls, exposure) (i64 i64 i64 i64 i64[] i64[]) i64
  context = ffkp_context(n, rank_debt) ## i64
  index = ffkp_index(mode, context) ## i64
  pulls[index] = pulls[index] + 1
  quanta = lane_quanta ## i64
  if quanta < 1
    quanta = 1
  exposure[index] = exposure[index] + quanta
  index

-> ffkp_record_reward(mode, n, rank_debt, reward, rewards) (i64 i64 i64 i64 i64[]) i64
  index = ffkp_index(mode, ffkp_context(n, rank_debt)) ## i64
  rewards[index] = rewards[index] + reward
  rewards[index]

-> ffkp_subspace_mask(n, nonce) (i64 i64) i64
  side = 2 ## i64
  if n >= 5
    side = 3
  span = n - side + 1 ## i64
  offset = nonce % span ## i64
  mask = 0 ## i64
  row = 0 ## i64
  while row < side
    col = 0 ## i64
    while col < side
      mask = mask | (1 << ((row + offset) * n + col + offset))
      col += 1
    row += 1
  mask

# Apply two or three exact split identities whose parts live in a small square
# subspace.  The identity is dimension-independent; changing the embedded
# subspace and source term supplies the cross-tensor transfer experiment.
-> ffkp_lifted_state(src, n, capacity, state_size, nonce, dslack, cycles, workq, wanderq)
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_best(src, us, vs, ws) ## i64
  if rank < 1
    return nil

  # One quarter of 5x5 lifted-identity launches first try the measured
  # five-bucket projective tunnel.  A 256-circuit cap costs about 40--60 ms
  # here; only a +1 endpoint is admitted, otherwise the ordinary lifted split
  # recipe below remains the fallback.  This reuses the existing pool row and
  # GPU continuation rather than adding another TUI strategy.
  if n == 5 && (nonce % 4) == 1
    projective_u = i64[capacity]
    projective_v = i64[capacity]
    projective_w = i64[capacity]
    projective_meta = i64[14]
    projective_rank = ffpc5_search(us,vs,ws,rank,256,nonce,projective_u,projective_v,projective_w,projective_meta) ## i64
    if projective_rank == rank + 1
      projective_state = i64[state_size]
      projective_loaded = ffw_init_terms_cap(projective_state,projective_u,projective_v,projective_w,projective_rank,n,capacity,60901 + nonce,dslack,cycles,workq,wanderq) ## i64
      if projective_loaded == projective_rank && ffw_verify_best_exact(projective_state,n) == 1
        return projective_state
  subspace = ffkp_subspace_mask(n, nonce) ## i64
  moves = 2 + (nonce % 2) ## i64
  move = 0 ## i64
  while move < moves && rank > 0
    source = (nonce * 17 + move * 31) % rank ## i64
    axis = (nonce + move) % 3 ## i64
    old = us[source] ## i64
    if axis == 1
      old = vs[source]
    if axis == 2
      old = ws[source]
    part = subspace & ((1 << (n * n)) - 1) ## i64
    # Vary the lifted coordinates while keeping a nonzero, nontrivial split.
    if (move & 1) == 1
      part = part ^ (part >> n)
    part = part & ((1 << (n * n)) - 1)
    if part == 0 || part == old
      bit = (nonce + move * 7) % (n * n) ## i64
      part = 1 << bit
      if part == old
        part = 1 << ((bit + 1) % (n * n))
    meta = i64[8]
    rank = ffe_split_with_part(us, vs, ws, rank, capacity, source, axis, part, meta)
    move += 1
  if rank < 1
    return nil
  candidate = i64[state_size]
  loaded = ffw_init_terms_cap(candidate, us, vs, ws, rank, n, capacity, 61001 + nonce, dslack, cycles, workq, wanderq) ## i64
  if loaded != rank
    return nil
  if ffw_verify_best_exact(candidate, n) != 1
    return nil
  candidate

# Search a bounded host beam of exact two-step recipes, then hand the selected
# shoulder to the ordinary GPU walker.  This strictly contains the old
# split+split seed family while adding mixed break/orbit/polarize paths.
-> ffkp_beam_recipe_state(src, n, capacity, state_size, nonce, dslack, cycles, workq, wanderq)
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  source_rank = ffw_export_best(src, source_u, source_v, source_w) ## i64
  if source_rank < 1 || capacity < source_rank + 2
    return nil
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  recipe = i64[3]
  meta = i64[8]
  depth = 2 ## i64
  # Five/six-dimensional frontiers have enough room for an occasional third
  # algebraic edge; the score still strongly penalizes additional rank debt.
  if n == 5 || n == 6
    depth = 3
  rank = ffbr_beam_search(source_u, source_v, source_w, source_rank, capacity, n, depth, 8, 63001 + nonce * 19, out_u, out_v, out_w, recipe, meta) ## i64
  if rank < 1 || rank > source_rank + 4
    return nil
  candidate = i64[state_size]
  loaded = ffw_init_terms_cap(candidate, out_u, out_v, out_w, rank, n, capacity, 63101 + nonce * 23, dslack, cycles, workq, wanderq) ## i64
  if loaded != rank || ffw_verify_best_exact(candidate, n) != 1
    return nil
  candidate
