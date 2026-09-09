# MFM3: preserve the complete MFM2 group plan, then try bank-backed 2x2
# grids and groups jointly on <=16-term equality components. A separate
# probe budget limits this pass; oversized/exhausted components keep MFM2.
use mixed_groups

# Status: grid probes/fallbacks/components, pair states, then the original
# group probes/fallbacks/components. Each probe/state pass has its own budget.
-> ffmx_plan(parent, words, cap, rank, costs, cost_words, heads, axes, out_words, scratch, scratch_words, memo, choice, memo_words, status, status_words, budget) (i64[] i64 i64 i64 i64[] i64 i64[] i64[] i64 i64[] i64 i64[] i64[] i64 i64[] i64 i64) i64
  if cost_words < 13 || status_words < 7
    return 0-1
  i = 10 ## i64
  while i < 13
    if costs[i] != 0-1 && (costs[i] < 1 || costs[i] > 128)
      return 0-1
    i += 1
  total = ffmg_plan(parent, words, cap, rank, costs, 10, heads, axes, out_words, scratch, scratch_words, memo, choice, memo_words, status, 4, budget) ## i64
  if total < 1
    return 0-1
  status[4] = status[0]
  status[5] = status[1]
  status[6] = status[2]
  status[0] = 0
  status[1] = 0
  status[2] = 0
  useful = 0 ## i64
  i = 10
  while i < 13
    if costs[i] > 0 && costs[i] < 4*costs[0]
      useful = 1
    i += 1
  if useful == 0
    # No extra eligible hyperedges: retain both the plan and its explicit
    # completion/fallback classification without a redundant DP pass.
    status[1] = status[5]
    status[2] = status[6]
    return total
  active = i64[3]
  equal = i64[48]
  sizes = i64[512]
  i = 0
  while i < rank
    scratch[i] = 0
    sizes[heads[i]] += 1
    i += 1
  axis = 0 ## i64
  while axis < 3
    k = 2 ## i64
    while k <= 4
      cost = ffmg_price(costs, axis, k) ## i64
      if cost > 0 && cost < k*costs[0]
        active[axis] = 1
      k += 1
    axis += 1
  kind = 3 ## i64
  while kind < 6
    if costs[7+kind] > 0 && costs[7+kind] < 4*costs[0]
      active[ffmx_first(kind)] = 1
      active[ffmx_second(kind)] = 1
    kind += 1
  start = 0 ## i64
  while start < rank
    if scratch[start] == 0
      scratch[rank] = start
      scratch[start] = 1
      count = 1 ## i64
      head = 0 ## i64
      while head < count
        left = scratch[rank+head] ## i64
        j = 0 ## i64
        while j < rank
          if scratch[j] == 0
            axis = 0
            while axis < 3
              if active[axis] == 1 && parent[axis*cap+left] == parent[axis*cap+j]
                scratch[j] = 1
                scratch[rank+count] = j
                count += 1
                break
              axis += 1
          j += 1
        head += 1
      status[2] += 1
      if count > 1
        gain = 0-1 ## i64
        if count <= 16 && status[0] < budget
          prior = 0 ## i64
          i = 0
          while i < count
            original = scratch[rank+i] ## i64
            if heads[original] == original
              prior += ffmg_price(costs, axes[original], sizes[original])
            axis = 0
            while axis < 3
              equal[axis*16+i] = 0
              j = 0 ## i64
              while j < count
                if parent[axis*cap+original] == parent[axis*cap+scratch[rank+j]]
                  equal[axis*16+i] = equal[axis*16+i] | (1 << j)
                j += 1
              axis += 1
            i += 1
          mask = (1 << count)-1 ## i64
          i = 0
          while i <= mask
            memo[i] = 0-1
            choice[i] = 0
            i += 1
          memo[0] = 0
          gain = ffmg_visit(mask, equal, costs, 13, memo, choice, status, budget)
          if gain >= 0
            price = count*costs[0]-gain ## i64
            if price > prior
              return 0-1
            total += price-prior
            while mask > 0
              group = choice[mask] & 65535 ## i64
              axis = choice[mask] >> 16
              if group == 0
                group = 1 << ffpk_ctz(mask)
                axis = 0-1
              remaining = group ## i64
              smallest = rank ## i64
              while remaining > 0
                original = scratch[rank+ffpk_ctz(remaining)] ## i64
                if original < smallest
                  smallest = original
                remaining = remaining & (remaining-1)
              remaining = group
              while remaining > 0
                original = scratch[rank+ffpk_ctz(remaining)] ## i64
                heads[original] = smallest
                axes[original] = axis
                remaining = remaining & (remaining-1)
              mask = mask ^ group
        if gain < 0
          status[1] += 1
    start += 1
  total
