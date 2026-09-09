# Read-only offline observers of the SAME walked state. Canonical ordering
# agrees with the automatic composer's deterministic fallback. Caller-owned
# scratch is reused; none of the walker's state, counters or RNG is changed.
use bud_parent_score
use ../lib/metaflip/composition/mixed_pairs
use ../lib/metaflip/composition/mixed_groups
use ../lib/metaflip/composition/mixed_grids
use ../lib/metaflip/fleet/refinement_artifacts

-> ffbp_mixed_parent(st, parent) (i64[] i64[]) i64
  rank = ffr_current_rank(st) ## i64
  if rank < 1 || rank > 512
    return 0
  i = 0 ## i64
  while i < rank
    slot = st[st[50]+i] ## i64
    axis = 0 ## i64
    while axis < 3
      parent[axis*512+i] = st[st[44+axis]+slot]
      axis += 1
    i += 1
  z = ffrf_sort(parent, 512, rank) ## i64
  rank

-> ffbp_mixed_costs(st, tables, observers, kind, scores, parent, costs, mates, axes, scratch, memo, choice, status, totals, budget) (i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  if observers < 1 || observers > 8 || kind < 1 || kind > 3
    return 0
  rank = ffbp_mixed_parent(st, parent) ## i64
  if rank < 1
    return 0
  width = 4 ## i64
  if kind == 2
    width = 10
  if kind == 3
    width = 13
  observer = 0 ## i64
  while observer < observers
    i = 0 ## i64
    while i < width
      costs[i] = tables[observer*width+i]
      i += 1
    price = ffbp_packing_plan(rank,kind,costs,parent,mates,axes,scratch,memo,choice,status,totals,budget) ## i64
    if price < 1
      return 0
    scores[observer+1] = price
    observer += 1
  1

# Optional primary objective. Its value steers chunk acceptance; computing
# it still cannot mutate the walk, RNG or exact-verifier counters. kind=1
# is the unchanged pair planner, kind=2 adds groups, kind=3 adds grids. Table/leaf
# binding remains the research caller's obligation before product admission.
-> ffbp_packing_cost(st, kind, costs, parent, mates, axes, scratch, memo, choice, status, totals, budget) (i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  rank = ffbp_mixed_parent(st, parent) ## i64
  ffbp_packing_plan(rank,kind,costs,parent,mates,axes,scratch,memo,choice,status,totals,budget)

# The observers share one canonical parent copy, not the walk or the plans.
# Each context gets its own full bounded solve and contributes to all counters.
-> ffbp_packing_plan(rank, kind, costs, parent, mates, axes, scratch, memo, choice, status, totals, budget) (i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  if rank < 1 || rank > 512 || kind < 1 || kind > 3
    return 0
  score = 0 ## i64
  if kind == 1
    score = ffmm_plan(parent, 3*512, 512, rank, costs, 4, mates, axes, 512, scratch, 6*512, memo, choice, 65536, status, 3, budget)
  elsif kind == 2
    score = ffmg_plan(parent, 3*512, 512, rank, costs, 10, mates, axes, 512, scratch, 6*512, memo, choice, 65536, status, 4, budget)
  else
    score = ffmx_plan(parent, 3*512, 512, rank, costs, 13, mates, axes, 512, scratch, 6*512, memo, choice, 65536, status, 7, budget)
  if score < 1
    return 0
  totals[0] += 1
  totals[1] += status[0]
  totals[2] += status[1]
  totals[3] += status[2]
  if kind >= 2
    totals[4] += status[3]
  if kind == 3
    totals[5] += status[4]
    totals[6] += status[5]
    totals[7] += status[6]
  score
