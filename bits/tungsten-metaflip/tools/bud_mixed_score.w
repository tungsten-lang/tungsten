# Read-only offline observers of the SAME walked state. Canonical ordering
# agrees with the automatic composer's deterministic fallback. Caller-owned
# scratch is reused; none of the walker's state, counters or RNG is changed.
use bud_parent_score
use ../lib/metaflip/composition/mixed_pairs
use ../lib/metaflip/fleet/refinement_artifacts

-> ffbp_mixed_costs(st, tables, observers, scores, parent, costs, mates, axes, scratch, memo, choice, status, totals, budget) (i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  rank = ffr_current_rank(st) ## i64
  if rank < 1 || rank > 512 || observers < 1 || observers > 8
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
  observer = 0 ## i64
  while observer < observers
    i = 0
    while i < 4
      costs[i] = tables[observer*4+i]
      i += 1
    price = ffmm_plan(parent, 3*512, 512, rank, costs, 4, mates, axes, 512, scratch, 6*512, memo, choice, 65536, status, 3, budget) ## i64
    if price < 1
      return 0
    scores[observer+1] = price
    totals[0] += 1
    totals[1] += status[0]
    totals[2] += status[1]
    totals[3] += status[2]
    observer += 1
  1
