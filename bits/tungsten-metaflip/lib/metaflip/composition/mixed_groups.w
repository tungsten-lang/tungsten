# Bank-backed disjoint groups of size 1..4. Preserve the pair plan on every
# oversized or probe-limited component. No group enumeration on the hot walk.
use mixed_pairs

-> ffmg_price(costs, axis, size) (i64[] i64 i64) i64
  if size == 1
    return costs[0]
  if axis >= 3
    return costs[7+axis]
  costs[1+3*(size-2)+axis]

# Grid kinds 3/4/5 share the U,V / U,W / V,W factor classes. Their
# elementary shapes are 2x1x2 / 1x2x2 / 2x2x1. The third factor map is
# arbitrary: the four distinct cells, not a rank-only price, justify it.
-> ffmx_first(kind) (i64) i64
  if kind == 5
    return 1
  0

-> ffmx_second(kind) (i64) i64
  if kind == 3
    return 1
  2

-> ffmx_fixed(kind) (i64) i64
  if kind == 3
    return 1
  if kind == 4
    return 0
  2

# Validate/reorder four members by the two factor classes (00,01,10,11).
# A repeated cell or third class is rejected before the output is touched.
-> ffmx_order(parent, cap, members, kind) (i64[] i64 i64[] i64) i64
  first = ffmx_first(kind) ## i64
  second = ffmx_second(kind) ## i64
  v0 = parent[first*cap+members[0]] ## i64
  w0 = parent[second*cap+members[0]] ## i64
  v1 = 0 ## i64
  w1 = 0 ## i64
  slots = i64[4]
  occupied = 0 ## i64
  i = 0 ## i64
  while i < 4
    v = parent[first*cap+members[i]] ## i64
    w = parent[second*cap+members[i]] ## i64
    cell = 0 ## i64
    if v != v0
      if v1 != 0 && v1 != v
        return 0
      v1 = v
      cell += 2
    if w != w0
      if w1 != 0 && w1 != w
        return 0
      w1 = w
      cell += 1
    if (occupied & (1 << cell)) != 0
      return 0
    occupied = occupied | (1 << cell)
    slots[cell] = members[i]
    i += 1
  if occupied != 15
    return 0
  i = 0
  while i < 4
    members[i] = slots[i]
    i += 1
  1

# Every recursive probe, including memo hits, consumes budget. choice packs
# a <=16-bit group mask and its axis; zero selects the singleton branch.
-> ffmg_visit(mask, equal, costs, slots, memo, choice, status, budget) (i64 i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if status[0] >= budget
    return 0-1
  status[0] += 1
  if memo[mask] >= 0
    return memo[mask]
  first = ffpk_ctz(mask) ## i64
  rest = mask ^ (1 << first) ## i64
  best = ffmg_visit(rest, equal, costs, slots, memo, choice, status, budget) ## i64
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
        tail = ffmg_visit(mask ^ pair, equal, costs, slots, memo, choice, status, budget) ## i64
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
          tail = ffmg_visit(mask ^ triple, equal, costs, slots, memo, choice, status, budget) ## i64
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
            tail = ffmg_visit(mask ^ group, equal, costs, slots, memo, choice, status, budget) ## i64
            if tail < 0
              return 0-1
            gain = 4*costs[0]-cost+tail ## i64
            if gain > best
              best = gain
              selected = group | (axis << 16)
    axis += 1
  if slots >= 13
    kind = 3 ## i64
    while kind < 6
      cost = costs[7+kind] ## i64
      if cost > 0 && cost < 4*costs[0]
        a0 = ffmx_first(kind) ## i64
        a1 = ffmx_second(kind) ## i64
        right = rest & equal[a0*16+first] & (65535 ^ equal[a1*16+first]) ## i64
        down = rest & equal[a1*16+first] & (65535 ^ equal[a0*16+first]) ## i64
        while right > 0
          j = ffpk_ctz(right) ## i64
          right = right & (right-1)
          remaining = down ## i64
          while remaining > 0
            # Failed rectangle probes count too; dense non-grids must not
            # hide unbounded work behind a small memo-state count.
            if status[0] >= budget
              return 0-1
            status[0] += 1
            k = ffpk_ctz(remaining) ## i64
            remaining = remaining & (remaining-1)
            opposite = rest & equal[a0*16+k] & equal[a1*16+j] ## i64
            while opposite > 0
              l = ffpk_ctz(opposite) ## i64
              opposite = opposite & (opposite-1)
              group = (1 << first) | (1 << j) | (1 << k) | (1 << l) ## i64
              tail = ffmg_visit(mask ^ group, equal, costs, slots, memo, choice, status, budget) ## i64
              if tail < 0
                return 0-1
              gain = 4*costs[0]-cost+tail ## i64
              if gain > best
                best = gain
                selected = group | (kind << 16)
      kind += 1
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
          exact_gain = ffmg_visit(mask, equal, costs, 10, memo, choice, status, budget)
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

# Ten group leaves, or thirteen with UV/UW/VW grids. Validate the complete
# plan and all available leaves before touching the packed output buffer.
-> ffmg_compose(parent, words, cap, rank, n, m, p, a, b, c, leaves, leaf_words, leafcap, costs, cost_words, heads, axes, plan_words, out, out_words) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64 i64 i64[] i64 i64[] i64[] i64 i64[] i64) i64
  if n < 1 || m < 1 || p < 1 || n > 63 || m > 63 || p > 63 || n*m > 63 || m*p > 63 || n*p > 63 || cap < 1 || cap > 4096 || rank < 1 || rank > cap || rank > 512 || words < 3*cap || a < 1 || a > 4 || b < 1 || b > 4 || c < 1 || c > 4 || leafcap < 1 || leafcap > 128 || leaf_words < 30*leafcap || cost_words < 10 || plan_words < rank
    return 0-1
  stride = ffpk_stride(n*a, m*b, p*c) ## i64
  if stride == 0
    return 0-1
  slots = 10 ## i64
  maxaxis = 2 ## i64
  if cost_words >= 13
    slots = 13
    maxaxis = 5
    if leaf_words < 39*leafcap
      return 0-1
  i = 0 ## i64
  while i < slots
    cost = costs[i] ## i64
    if (i < 4 && cost < 1) || (cost != 0-1 && (cost < 1 || cost > leafcap))
      return 0-1
    if cost > 0
      ln = a ## i64
      lm = b ## i64
      lp = c ## i64
      if i >= 10
        fixed = ffmx_fixed(i-7) ## i64
        if fixed != 0
          ln *= 2
        if fixed != 1
          lm *= 2
        if fixed != 2
          lp *= 2
      elsif i > 0
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
    if head < 0 || head > i || heads[head] != head || axis < 0-1 || axis > maxaxis || axes[head] != axis
      return 0-1
    if head != i && (axis < 0 || (axis < 3 && parent[axis*cap+i] != parent[axis*cap+head]))
      return 0-1
    sizes[head] += 1
    if sizes[head] > 4
      return 0-1
    i += 1
  price = 0 ## i64
  members = i64[4]
  i = 0
  while i < rank
    if heads[i] == i
      if (sizes[i] == 1 && axes[i] != 0-1) || (sizes[i] > 1 && axes[i] < 0)
        return 0-1
      if axes[i] >= 3
        if sizes[i] != 4
          return 0-1
        count = 0 ## i64
        j = i ## i64
        while j < rank
          if heads[j] == i
            members[count] = j
            count += 1
          j += 1
        if ffmx_order(parent, cap, members, axes[i]) != 1
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
  i = 0
  while i < rank
    if heads[i] == i
      size = sizes[i] ## i64
      axis = axes[i] ## i64
      slot = 0 ## i64
      if size > 1
        slot = 1+3*(size-2)+axis
      if axis >= 3
        slot = 7+axis
      count = 0 ## i64
      j = i ## i64
      while j < rank
        if heads[j] == i
          members[count] = j
          count += 1
        j += 1
      if axis >= 3
        ordered = ffmx_order(parent, cap, members, axis) ## i64
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
          row_dim = 0 ## i64
          if factor == 1
            row_scale = b
            row_dim = 1
          if factor > 0
            column_scale = c
            parentcols = p
            column_dim = 2
            leafcols = c
          if expanded == column_dim
            leafcols *= size
          if axis >= 3 && ffmx_fixed(axis) != column_dim
            leafcols *= 2
          value = leaves[(slot*3+factor)*leafcap+l] ## i64
          while value > 0
            bit = ffmm_bit(value) ## i64
            lr = bit / leafcols ## i64
            lc = bit%leafcols ## i64
            member = lr / row_scale+lc / column_scale ## i64
            if axis >= 3
              # Coordinates for the two independent factor values. The
              # shared dimension has size one and contributes no index.
              d0 = 0 ## i64
              d1 = 0 ## i64
              d2 = 0 ## i64
              if row_dim == 0
                d0 = lr / row_scale
              else
                d1 = lr / row_scale
              if column_dim == 1
                d1 = lc / column_scale
              else
                d2 = lc / column_scale
              member = 2*d0+d2
              if axis == 4
                member = 2*d1+d2
              if axis == 5
                member = 2*d1+d0
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
