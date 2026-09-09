# Bank-backed disjoint groups of size 1..4. Preserve the pair plan on every
# oversized or probe-limited component. No group enumeration on the hot walk.
use mixed_pairs

-> ffmg_price(costs, axis, size) (i64[] i64 i64) i64
  if size == 1
    return costs[0]
  costs[1+3*(size-2)+axis]

# Every recursive probe, including memo hits, consumes budget. choice packs
# a <=16-bit group mask and its axis; zero selects the singleton branch.
-> ffmg_visit(mask, equal, costs, memo, choice, status, budget) (i64 i64[] i64[] i64[] i64[] i64[] i64) i64
  if status[0] >= budget
    return 0-1
  status[0] += 1
  if memo[mask] >= 0
    return memo[mask]
  first = ffpk_ctz(mask) ## i64
  rest = mask ^ (1 << first) ## i64
  best = ffmg_visit(rest, equal, costs, memo, choice, status, budget) ## i64
  if best < 0
    return 0-1
  selected = 0 ## i64
  axis = 0 ## i64
  while axis < 3
    remaining = rest & equal[axis*16+first] ## i64
    while remaining > 0
      j = ffpk_ctz(remaining) ## i64
      remaining = remaining & (remaining-1)
      pair = (1 << first) | (1 << j) ## i64
      cost = ffmg_price(costs, axis, 2) ## i64
      if cost > 0 && cost < 2*costs[0]
        tail = ffmg_visit(mask ^ pair, equal, costs, memo, choice, status, budget) ## i64
        if tail < 0
          return 0-1
        gain = 2*costs[0]-cost+tail ## i64
        if gain > best
          best = gain
          selected = pair | (axis << 16)
      third = remaining ## i64
      while third > 0
        k = ffpk_ctz(third) ## i64
        third = third & (third-1)
        triple = pair | (1 << k) ## i64
        cost = ffmg_price(costs, axis, 3)
        if cost > 0 && cost < 3*costs[0]
          tail = ffmg_visit(mask ^ triple, equal, costs, memo, choice, status, budget) ## i64
          if tail < 0
            return 0-1
          gain = 3*costs[0]-cost+tail ## i64
          if gain > best
            best = gain
            selected = triple | (axis << 16)
        fourth = third ## i64
        cost = ffmg_price(costs, axis, 4)
        if cost > 0 && cost < 4*costs[0]
          while fourth > 0
            l = ffpk_ctz(fourth) ## i64
            fourth = fourth & (fourth-1)
            group = triple | (1 << l) ## i64
            tail = ffmg_visit(mask ^ group, equal, costs, memo, choice, status, budget) ## i64
            if tail < 0
              return 0-1
            gain = 4*costs[0]-cost+tail ## i64
            if gain > best
              best = gain
              selected = group | (axis << 16)
    axis += 1
  memo[mask] = best
  choice[mask] = selected
  best

# First four costs are the existing pair context. The next two triples are
# size-3 and size-4 costs; -1 means no bank witness. heads[i] is the smallest
# original index in i's group. status = group probes, group fallback
# components, group components, pair states. The same budget separately
# bounds old pair states and new group probes. Invalid calls do not edit plans.
-> ffmg_plan(parent, words, cap, rank, costs, cost_words, heads, axes, out_words, scratch, scratch_words, memo, choice, memo_words, status, status_words, budget) (i64[] i64 i64 i64 i64[] i64 i64[] i64[] i64 i64[] i64 i64[] i64[] i64 i64[] i64 i64) i64
  if cap < 1 || cap > 4096 || rank < 1 || rank > cap || rank > 512 || words < 3*cap || cost_words < 10 || out_words < rank || scratch_words < 6*rank || memo_words < 65536 || status_words < 4 || budget < 1 || budget > 1000000
    return 0-1
  i = 0 ## i64
  while i < 10
    if costs[i] != 0-1 && (costs[i] < 1 || costs[i] > 128)
      return 0-1
    if i < 4 && costs[i] < 1
      return 0-1
    i += 1
  total = ffmm_plan(parent, words, cap, rank, costs, 4, heads, axes, out_words, scratch, scratch_words, memo, choice, memo_words, status, 3, budget) ## i64
  if total < 1
    return 0-1
  status[3] = status[0]
  status[0] = 0
  status[1] = 0
  status[2] = 0
  i = 0
  while i < rank
    if heads[i] > i
      heads[i] = i
    scratch[i] = 0
    i += 1
  active = i64[3]
  equal = i64[48]
  axis = 0 ## i64
  while axis < 3
    k = 2 ## i64
    while k <= 4
      cost = ffmg_price(costs, axis, k) ## i64
      if cost > 0 && cost < k*costs[0]
        active[axis] = 1
      k += 1
    axis += 1
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
        exact_gain = 0-1 ## i64
        if count <= 16 && status[0] < budget
          i = 0
          prior = 0 ## i64
          while i < count
            original = scratch[rank+i] ## i64
            if heads[original] == original
              if axes[original] < 0
                prior += costs[0]
              else
                prior += costs[axes[original]+1]
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
          exact_gain = ffmg_visit(mask, equal, costs, memo, choice, status, budget)
          if exact_gain >= 0
            price = count*costs[0]-exact_gain ## i64
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
        if exact_gain < 0
          status[1] += 1
    start += 1
  total

# Ten oriented leaves, matching the cost slots above. Validate the complete
# plan and all available leaves before touching the packed output buffer.
-> ffmg_compose(parent, words, cap, rank, n, m, p, a, b, c, leaves, leaf_words, leafcap, costs, cost_words, heads, axes, plan_words, out, out_words) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64 i64 i64[] i64 i64[] i64[] i64 i64[] i64) i64
  if n < 1 || m < 1 || p < 1 || n > 63 || m > 63 || p > 63 || n*m > 63 || m*p > 63 || n*p > 63 || cap < 1 || cap > 4096 || rank < 1 || rank > cap || rank > 512 || words < 3*cap || a < 2 || a > 4 || b < 2 || b > 4 || c < 2 || c > 4 || leafcap < 1 || leafcap > 128 || leaf_words < 30*leafcap || cost_words < 10 || plan_words < rank
    return 0-1
  stride = ffpk_stride(n*a, m*b, p*c) ## i64
  if stride == 0
    return 0-1
  i = 0 ## i64
  while i < 10
    cost = costs[i] ## i64
    if (i < 4 && cost < 1) || (cost != 0-1 && (cost < 1 || cost > leafcap))
      return 0-1
    if cost > 0
      ln = a ## i64
      lm = b ## i64
      lp = c ## i64
      if i > 0
        axis = (i-1)%3 ## i64
        size = 2+(i-1)/3 ## i64
        if axis == 0
          lp *= size
        if axis == 1
          ln *= size
        if axis == 2
          lm *= size
      f = 0 ## i64
      while f < 3
        width = ffpk_width(ln, lm, lp, f) ## i64
        if width > 63
          return 0-1
        j = 0 ## i64
        while j < cost
          value = leaves[(3*i+f)*leafcap+j] ## i64
          if value <= 0 || (width < 63 && (value >> width) != 0)
            return 0-1
          j += 1
        f += 1
    i += 1
  sizes = i64[512]
  i = 0
  while i < rank
    f = 0 ## i64
    while f < 3
      width = ffpk_width(n, m, p, f) ## i64
      value = parent[f*cap+i] ## i64
      if value <= 0 || (width < 63 && (value >> width) != 0)
        return 0-1
      f += 1
    head = heads[i] ## i64
    axis = axes[i] ## i64
    if head < 0 || head > i || heads[head] != head || axis < 0-1 || axis > 2 || axes[head] != axis
      return 0-1
    if head != i && (axis < 0 || parent[axis*cap+i] != parent[axis*cap+head])
      return 0-1
    sizes[head] += 1
    if sizes[head] > 4
      return 0-1
    i += 1
  price = 0 ## i64
  i = 0
  while i < rank
    if heads[i] == i
      if (sizes[i] == 1 && axes[i] != 0-1) || (sizes[i] > 1 && axes[i] < 0)
        return 0-1
      cost = ffmg_price(costs, axes[i], sizes[i]) ## i64
      if cost < 1
        return 0-1
      price += cost
    i += 1
  if price < 1 || price > 16384 || out_words < 3*stride*price
    return 0-1
  i = 0
  while i < 3*stride*price
    out[i] = 0
    i += 1
  output = 0 ## i64
  members = i64[4]
  i = 0
  while i < rank
    if heads[i] == i
      size = sizes[i] ## i64
      axis = axes[i] ## i64
      slot = 0 ## i64
      if size > 1
        slot = 1+3*(size-2)+axis
      count = 0 ## i64
      j = i ## i64
      while j < rank
        if heads[j] == i
          members[count] = j
          count += 1
        j += 1
      l = 0 ## i64
      while l < costs[slot]
        factor = 0 ## i64
        while factor < 3
          row_scale = a ## i64
          column_scale = b ## i64
          parentcols = m ## i64
          leafcols = b ## i64
          expanded = 0-1 ## i64
          if axis == 0
            expanded = 2
          if axis == 1
            expanded = 0
          if axis == 2
            expanded = 1
          column_dim = 1 ## i64
          if factor == 1
            row_scale = b
          if factor > 0
            column_scale = c
            parentcols = p
            column_dim = 2
            leafcols = c
          if expanded == column_dim
            leafcols *= size
          value = leaves[(slot*3+factor)*leafcap+l] ## i64
          while value > 0
            bit = ffmm_bit(value) ## i64
            lr = bit / leafcols ## i64
            lc = bit%leafcols ## i64
            member = lr / row_scale+lc / column_scale ## i64
            outer = parent[factor*cap+members[member]] ## i64
            while outer > 0
              obit = ffmm_bit(outer) ## i64
              mapped = ((obit / parentcols)*row_scale+lr%row_scale)*(parentcols*column_scale)+(obit%parentcols)*column_scale+lc%column_scale ## i64
              offset = (3*output+factor)*stride+mapped/32 ## i64
              out[offset] = out[offset] ^ (1 << (mapped%32))
              outer = outer ^ (1 << obit)
            value = value ^ (1 << bit)
          factor += 1
        output += 1
        l += 1
    i += 1
  ffpk_canonicalize(out, out_words, output, stride)
