# Disjoint mixed-axis pairs. Small components use exact weighted matching;
# oversized/state-limited components retain the best of six legal greedy
# axis orders. This optimizes a bounded formula family, not tensor rank.
use packed

-> ffmm_bit(value) (i64) i64
  if (value & 4294967295) == 0
    return 32+ffpk_ctz(value >> 32)
  ffpk_ctz(value & 4294967295)

-> ffmm_edge(parent, cap, left, right, costs) (i64[] i64 i64 i64 i64[]) i64
  selected = 0-1 ## i64
  saving = 0 ## i64
  axis = 0 ## i64
  while axis < 3
    gain = 2*costs[0]-costs[axis+1] ## i64
    if gain > saving && parent[axis*cap+left] == parent[axis*cap+right]
      saving = gain
      selected = axis
    axis += 1
  selected

-> ffmm_visit(mask, weights, memo, choice, status, budget) (i64 i64[] i64[] i64[] i64[] i64) i64
  if memo[mask] >= 0
    return memo[mask]
  if status[0] >= budget
    return 0-1
  status[0] += 1
  first = ffpk_ctz(mask) ## i64
  rest = mask ^ (1 << first) ## i64
  best = ffmm_visit(rest, weights, memo, choice, status, budget) ## i64
  if best < 0
    return 0-1
  partner = 0-1 ## i64
  remaining = rest ## i64
  while remaining > 0
    j = ffpk_ctz(remaining) ## i64
    if weights[first*16+j] > 0
      tail = ffmm_visit(rest ^ (1 << j), weights, memo, choice, status, budget) ## i64
      if tail < 0
        return 0-1
      gain = weights[first*16+j]+tail ## i64
      if gain > best
        best = gain
        partner = j
    remaining = remaining & (remaining-1)
  memo[mask] = best
  choice[mask] = partner
  best

# parent/output slabs are disjoint. scratch: visited, component, trial mate,
# trial axis, best mate, best axis. memo/choice each
# hold 2^16 entries and are reused across every component/context by callers.
# status = [visited states, fallback components, total components].
-> ffmm_plan(parent, words, cap, rank, costs, cost_words, mates, axes, out_words, scratch, scratch_words, memo, choice, memo_words, status, status_words, budget) (i64[] i64 i64 i64 i64[] i64 i64[] i64[] i64 i64[] i64 i64[] i64[] i64 i64[] i64 i64) i64
  if cap < 1 || cap > 4096 || rank < 1 || rank > cap || rank > 512 || words < 3*cap || cost_words < 4 || out_words < rank || scratch_words < 6*rank || memo_words < 65536 || status_words < 3 || budget < 1 || budget > 1000000
    return 0-1
  i = 0 ## i64
  while i < 4
    if costs[i] < 1 || costs[i] > 128
      return 0-1
    i += 1
  i = 0
  while i < rank
    if parent[i] <= 0 || parent[cap+i] <= 0 || parent[2*cap+i] <= 0
      return 0-1
    i += 1
  status[0] = 0
  status[1] = 0
  status[2] = 0
  i = 0
  while i < rank
    scratch[i] = 0
    mates[i] = i
    axes[i] = 0-1
    i += 1
  total = rank*costs[0] ## i64
  weights = i64[256]
  labels = i64[256]
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
          if scratch[j] == 0 && ffmm_edge(parent, cap, left, j, costs) >= 0
            scratch[j] = 1
            scratch[rank+count] = j
            count += 1
          j += 1
        head += 1
      status[2] += 1
      best_gain = 0 ## i64
      mode = 0 ## i64
      while mode < 6
        i = 0
        while i < count
          scratch[2*rank+i] = i
          scratch[3*rank+i] = 0-1
          if mode == 0
            scratch[4*rank+i] = i
            scratch[5*rank+i] = 0-1
          i += 1
        gain = 0 ## i64
        pass = 0 ## i64
        while pass < 3
          axis = mode/2 ## i64
          if pass > 0
            axis = (mode/2+pass)%3
            if mode%2 == 1
              axis = (mode/2+3-pass)%3
          saving = 2*costs[0]-costs[axis+1] ## i64
          if saving > 0
            i = 0
            while i < count
              if scratch[2*rank+i] == i
                j = i+1 ## i64
                while j < count
                  if scratch[2*rank+j] == j && parent[axis*cap+scratch[rank+i]] == parent[axis*cap+scratch[rank+j]]
                    scratch[2*rank+i] = j
                    scratch[2*rank+j] = i
                    scratch[3*rank+i] = axis
                    scratch[3*rank+j] = axis
                    gain += saving
                    break
                  j += 1
              i += 1
          pass += 1
        if gain > best_gain
          best_gain = gain
          i = 0
          while i < count
            scratch[4*rank+i] = scratch[2*rank+i]
            scratch[5*rank+i] = scratch[3*rank+i]
            i += 1
        mode += 1
      exact_gain = 0-1 ## i64
      if count == 1
        exact_gain = 0
      elsif count <= 16 && status[0] < budget
        i = 0
        while i < count
          j = 0 ## i64
          while j < count
            label = ffmm_edge(parent, cap, scratch[rank+i], scratch[rank+j], costs) ## i64
            labels[i*16+j] = label
            weights[i*16+j] = 0
            if label >= 0 && i != j
              weights[i*16+j] = 2*costs[0]-costs[label+1]
            j += 1
          i += 1
        mask = (1 << count)-1 ## i64
        i = 0
        while i <= mask
          memo[i] = 0-1
          choice[i] = 0-1
          i += 1
        memo[0] = 0
        exact_gain = ffmm_visit(mask, weights, memo, choice, status, budget)
        if exact_gain >= 0
          if exact_gain < best_gain
            return 0-1
          best_gain = exact_gain
          i = 0
          while i < count
            scratch[4*rank+i] = i
            scratch[5*rank+i] = 0-1
            i += 1
          while mask != 0
            i = ffpk_ctz(mask)
            j = choice[mask] ## i64
            mask = mask ^ (1 << i)
            if j >= 0
              scratch[4*rank+i] = j
              scratch[4*rank+j] = i
              scratch[5*rank+i] = labels[i*16+j]
              scratch[5*rank+j] = labels[i*16+j]
              mask = mask ^ (1 << j)
      if count > 1 && exact_gain < 0
        status[1] += 1
      total -= best_gain
      i = 0
      while i < count
        original = scratch[rank+i] ## i64
        mates[original] = scratch[rank+scratch[4*rank+i]]
        axes[original] = scratch[5*rank+i]
        i += 1
    start += 1
  total

# Four oriented leaves: singleton <a,b,c>, then pairs sharing U, V, W.
# Prices and indices never replace the later full wide-tensor identity check.
-> ffmm_compose(parent, words, cap, rank, n, m, p, a, b, c, leaves, leaf_words, leafcap, costs, cost_words, mates, axes, plan_words, out, out_words) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64 i64 i64[] i64 i64[] i64[] i64 i64[] i64) i64
  if n < 1 || m < 1 || p < 1 || n > 63 || m > 63 || p > 63 || n*m > 63 || m*p > 63 || n*p > 63 || cap < 1 || cap > 4096 || rank < 1 || rank > cap || rank > 512 || words < 3*cap || a < 1 || a > 4 || b < 1 || b > 4 || c < 1 || c > 4 || leafcap < 1 || leafcap > 128 || leaf_words < 12*leafcap || cost_words < 4 || plan_words < rank
    return 0-1
  stride = ffpk_stride(n*a, m*b, p*c) ## i64
  if stride == 0
    return 0-1
  price = 0 ## i64
  i = 0 ## i64
  while i < 4
    if costs[i] < 1 || costs[i] > leafcap
      return 0-1
    ln = a ## i64
    lm = b ## i64
    lp = c ## i64
    if i == 1
      lp *= 2
    if i == 2
      ln *= 2
    if i == 3
      lm *= 2
    f = 0 ## i64
    while f < 3
      j = 0 ## i64
      while j < costs[i]
        value = leaves[(3*i+f)*leafcap+j] ## i64
        if value <= 0 || (value >> ffpk_width(ln, lm, lp, f)) != 0
          return 0-1
        j += 1
      f += 1
    i += 1
  i = 0
  while i < rank
    f = 0 ## i64
    while f < 3
      width = ffpk_width(n, m, p, f) ## i64
      value = parent[f*cap+i] ## i64
      if value <= 0 || (width < 63 && (value >> width) != 0)
        return 0-1
      f += 1
    other = mates[i] ## i64
    axis = axes[i] ## i64
    if other < 0 || other >= rank || mates[other] != i || axis < 0-1 || axis > 2 || axes[other] != axis
      return 0-1
    if (other == i && axis != 0-1) || (other != i && (axis < 0 || parent[axis*cap+i] != parent[axis*cap+other]))
      return 0-1
    if other >= i
      price += costs[axis+1]
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
    other = mates[i] ## i64
    if other >= i
      axis = axes[i] ## i64
      l = 0 ## i64
      while l < costs[axis+1]
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
            leafcols *= 2
          value = leaves[((axis+1)*3+factor)*leafcap+l] ## i64
          while value > 0
            bit = ffmm_bit(value) ## i64
            lr = bit / leafcols ## i64
            lc = bit%leafcols ## i64
            member = lr / row_scale+lc / column_scale ## i64
            if member < 0 || member > 1 || (axis < 0 && member != 0)
              return 0-1
            index = i ## i64
            if member == 1
              index = other
            outer = parent[factor*cap+index] ## i64
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
