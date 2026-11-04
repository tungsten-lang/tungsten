# Bounded common-net proposals. Geometry is recovered from the current CNF.
# Fixed scratch offsets avoid allocation in every move and score evaluation.
# Geometry: two 3072-word surface transition tables (square, rotation,
# direction -> neighbor, transported rotation, edge), then quads at6144 and
# corners at6656. Scratch uses64-word cell vectors and128-word edge/hash
# vectors: mapping/rotation/inverse0/64/128, best192/256, backup320/384,
# kept edges448/576, degrees704, components768, planar embedding832/896/960,
# BFS1024, overlap hash1088/1216/1344, patch1472..1855, path1856..2559,
# path-coordinate bucket heads2560..2687 and links2688..2751. Words2752/2753
# count coordinate lookups and inspected chain entries across restarts.
# State0..6 describes geometry/anchors;7..15 tracks search;16..23 holds the
# current score components;24..29 counts candidates, stop, paths, moves,
# rejected moves and path nodes;30 is the fresh-path restart period.
use atomic_stop

-> wassat_box_net_rand(rng, limit) (u64[] i64) i64
  x = rng[0] ## u64
  x ^= x << 13
  x ^= x >> 7
  x ^= x << 17
  rng[0] = x
  modulus = limit ## u64
  x % modulus

-> wassat_box_net_step(b, i, o, d) (i64 i64 i64 i64) i64
  b * 3072 + i * 48 + o * 12 + d * 3

-> wassat_box_net_has(rng, index, bit) (u64[] i64 i64) i64
  word = rng[index] ## u64
  shift = bit ## u64
  value = (word >> shift) & 1 ## u64
  value

-> wassat_box_net_toggle(rng, index, bit) (u64[] i64 i64) i64
  word = rng[index] ## u64
  mask = 1 ## u64
  mask <<= bit
  word ^= mask
  rng[index] = word
  0

-> wassat_box_net_single(rng, index, bit) (u64[] i64 i64) i64
  mask = 1 ## u64
  mask <<= bit
  rng[index] = mask
  0

-> wassat_box_net_dx(d) (i64) i64
  d == 0 ? 1 : (d == 1 ? -1 : 0)

-> wassat_box_net_dy(d) (i64) i64
  d == 2 ? 1 : (d == 3 ? -1 : 0)

-> wassat_box_net_swap(s, a, b) (i64[] i64 i64) i64
  t = s[a] ## i64
  s[a] = s[b]
  s[b] = t
  0

-> wassat_box_net_copy(s, to, from, n) (i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    s[to+i] = s[from+i]
    i += 1
  0

-> wassat_box_net_inverse(s, n) (i64[] i64) i64
  i = 0 ## i64
  while i < n
    s[128+s[i]] = i
    i += 1
  0

-> wassat_box_net_evaluate(g, s, m) (i64[] i64[] i64[]) i64
  n = m[0] ## i64
  m[7] += 1
  k = 16 ## i64
  while k <= 23
    m[k] = 0
    k += 1
  k = 448
  while k < 1024
    s[k] = 0
    k += 1
  u = 0 ## i64
  while u < n
    d = 0 ## i64
    while d < 4
      a = wassat_box_net_step(0, u, 0, d) ## i64
      v = g[a] ## i64
      if u <= v
        b = wassat_box_net_step(1, s[u], s[64+u], d) ## i64
        if g[b] == s[v] && s[64+v] == ((g[b+1]-g[a+1]+4) & 3)
          s[448+g[a+2]] = 1
          s[576+g[b+2]] = 1
          s[704+u] += 1
          s[704+v] += 1
          m[16] += 1
      d += 1
    u += 1
  # Degrees of earlier endpoints were not final during the edge loop.
  m[17] = 0
  u = 0
  while u < n
    m[17] += 1 if s[704+u] == 0
    u += 1
  b = 0
  while b < 2
    q = 0 ## i64
    while q < m[3+b]
      k = 0
      j = 0 ## i64
      while j < 4
        k += s[448+b*128+g[6144+b*256+q*4+j]]
        j += 1
      m[19] += 1 if k == 3
      q += 1
    q = 0
    while q < m[5+b]
      k = 0
      j = 0
      while j < 3
        k += s[448+b*128+g[6656+b*24+q*3+j]]
        j += 1
      m[20] += 1 if k == 3
      q += 1
    b += 1
  root = 0 ## i64
  while root < n
    if s[768+root] == 0
      m[18] += 1
      s[768+root] = m[18]
      front = 0 ## i64
      back = 1 ## i64
      s[1024] = root
      while front < back
        u = s[1024+front]
        front += 1
        d = 0
        while d < 4
          a = wassat_box_net_step(0, u, s[832+u], d)
          if s[448+g[a+2]] != 0
            v = g[a]
            x = s[896+u] + wassat_box_net_dx(d) ## i64
            y = s[960+u] + wassat_box_net_dy(d) ## i64
            if s[768+v] == 0
              s[768+v] = m[18]
              s[832+v] = g[a+1]
              s[896+v] = x
              s[960+v] = y
              s[1024+back] = v
              back += 1
            elsif s[832+v] != g[a+1] || s[896+v] != x || s[960+v] != y
              m[21] += 1
          d += 1
    root += 1
  m[14] += 1
  if m[14] >= 2147483647
    m[14] = 1
    k = 1216
    while k < 1344
      s[k] = 0
      k += 1
  i = 0 ## i64
  while i < n
    key = (s[768+i] << 16) | ((s[896+i]+64) << 8) | (s[960+i]+64) ## i64
    slot = ((key * 2654435761) & 4294967295) >> 25 ## i64
    while s[1216+slot] == m[14] && s[1088+slot] != key
      slot = (slot+1) & 127
    if s[1216+slot] != m[14]
      s[1216+slot] = m[14]
      s[1088+slot] = key
      s[1344+slot] = 0
    m[22] += s[1344+slot]
    s[1344+slot] += 1
    m[23] += 1 if s[768+i] == 1
    i += 1
  anchor_penalty = s[769] == 1 ? 0 : 2048 ## i64
  anchor_penalty + 32*(n-m[23]) + 2*n-m[16] + 8*m[17] + 4*(m[18]-1) + 32*m[19] + 64*m[20] + 32*m[21] + 64*m[22]

-> wassat_box_net_block(g, s, m, rng, start, target, orientation, limit) (i64[] i64[] i64[] u64[] i64 i64 i64 i64) i64
  n = m[0] ## i64
  i = 0 ## i64
  while i < n
    s[1472+i] = 0
    s[1536+i] = -1
    s[1664+i] = 0
    s[1792+i] = -1
    i += 1
  s[1728] = start
  s[1472+start] = 1
  s[1536+start] = target
  s[1600+start] = orientation
  s[1664+target] = 1
  head = 0 ## i64
  tail = 1 ## i64
  while head < tail
    u = s[1728+head] ## i64
    head += 1
    d = 0 ## i64
    while d < 4
      a = wassat_box_net_step(0,u,0,d) ## i64
      v = g[a] ## i64
      old = wassat_box_net_step(1,s[u],s[64+u],d) ## i64
      if g[old] == s[v] && s[64+v] == ((g[old+1]-g[a+1]+4) & 3)
        step_next = wassat_box_net_step(1,s[1536+u],s[1600+u],d) ## i64
        nv = g[step_next] ## i64
        nr = (g[step_next+1]-g[a+1]+4) & 3 ## i64
        if s[1472+v] != 0
          return 0 if s[1536+v] != nv || s[1600+v] != nr
        elsif tail < limit
          return 0 if s[1664+nv] != 0
          s[1472+v] = 1
          s[1536+v] = nv
          s[1600+v] = nr
          s[1664+nv] = 1
          s[1728+tail] = v
          tail += 1
      d += 1
  return 0 if tail == n
  u = 0
  while u < n
    s[1792+s[1536+u]] = s[u] if s[1472+u] != 0
    u += 1
  u = 0
  while u < n
    if s[1472+u] == 0
      v = s[u]
      steps = 0 ## i64
      while s[1792+v] >= 0
        v = s[1792+v]
        steps += 1
        return 0 if steps > n
      s[1536+u] = v
      s[1600+u] = v == s[u] ? s[64+u] : wassat_box_net_rand(rng,4)
    u += 1
  return 0 if s[1536] != m[1] || s[1600] != 0 || s[1537] != m[2]
  z = wassat_box_net_copy(s,0,1536,n) ## i64
  z = wassat_box_net_copy(s,64,1600,n)
  z = wassat_box_net_inverse(s,n)
  1

-> wassat_box_net_poll(m, stop, deadline) (i64[] i64[] i64) i64
  m[15] += 1
  if wassat_stop_load(stop) != 0
    m[25] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[25] = 2
  m[25]

# Return the path depth at a coordinate, or -1. Bucket chains contain only
# active path entries; backtracking pops the last insertion in that bucket.
-> wassat_box_net_path_find(s, x, y) (i64[] i64 i64) i64
  s[2752] += 1
  slot = (x * 73 + y * 97) & 127 ## i64
  item = s[2560+slot] ## i64
  while item != 0
    s[2753] += 1
    k = item-1 ## i64
    return k if s[2112+k] == x && s[2176+k] == y
    item = s[2688+k]
  -1

-> wassat_box_net_path(g, s, m, rng, stop, deadline, depth) (i64[] i64[] i64[] u64[] i64[] i64 i64) i64
  m[11] += 1
  return 0 if m[11] > 20000
  return 0 if (m[11] & 255) == 0 && wassat_box_net_poll(m,stop,deadline) != 0
  u = s[1856+depth] ## i64
  v = s[1920+depth] ## i64
  ou = s[1984+depth] ## i64
  ov = s[2048+depth] ## i64
  if u == 1
    m[12] = depth+1
    return v == m[2] ? 1 : 0
  return 0 if depth >= m[13]
  dirs = 2240+depth*4 ## i64
  d = 0 ## i64
  while d < 4
    s[dirs+d] = d
    d += 1
  d = 3
  while d > 0
    z = wassat_box_net_swap(s,dirs+d,dirs+wassat_box_net_rand(rng,d+1)) ## i64
    d -= 1
  dd = 0 ## i64
  while dd < 4
    d = s[dirs+dd]
    a = wassat_box_net_step(0,u,ou,d) ## i64
    b = wassat_box_net_step(1,v,ov,d) ## i64
    av = g[a] ## i64
    bv = g[b] ## i64
    valid = 1 ## i64
    valid = 0 if wassat_box_net_has(rng,1,av) != 0 || wassat_box_net_has(rng,2,bv) != 0 || ((av == 1) != (bv == m[2]))
    x = s[2112+depth] + wassat_box_net_dx(d) ## i64
    y = s[2176+depth] + wassat_box_net_dy(d) ## i64
    # Only the occupied square and its four planar neighbors can conflict.
    # Exact coordinates resolve hash collisions; active depths are chained.
    if valid != 0
      valid = 0 if wassat_box_net_path_find(s,x,y) >= 0
      q = 0 ## i64
      while q < 4 && valid != 0
        k = wassat_box_net_path_find(s,x+wassat_box_net_dx(q),y+wassat_box_net_dy(q)) ## i64
        if k >= 0
          aa = wassat_box_net_step(0,av,g[a+1],q) ## i64
          bb = wassat_box_net_step(1,bv,g[b+1],q) ## i64
          valid = 0 if g[aa] != s[1856+k] || g[aa+1] != s[1984+k] || g[bb] != s[1920+k] || g[bb+1] != s[2048+k]
        q += 1
    if valid != 0
      s[1857+depth] = av
      s[1921+depth] = bv
      s[1985+depth] = g[a+1]
      s[2049+depth] = g[b+1]
      s[2113+depth] = x
      s[2177+depth] = y
      z = wassat_box_net_toggle(rng,1,av) ## i64
      z = wassat_box_net_toggle(rng,2,bv)
      slot = (x * 73 + y * 97) & 127 ## i64
      # Recursion inserts and removes entries in stack order, even when
      # several coordinates share a bucket. A failed branch restores its head.
      s[2689+depth] = s[2560+slot]
      s[2560+slot] = depth+2
      return 1 if wassat_box_net_path(g,s,m,rng,stop,deadline,depth+1) != 0
      s[2560+slot] = s[2689+depth]
      z = wassat_box_net_toggle(rng,1,av)
      z = wassat_box_net_toggle(rng,2,bv)
    dd += 1
  0

-> wassat_box_net_seed(g, s, m, rng, stop, deadline) (i64[] i64[] i64[] u64[] i64[] i64) i64
  n = m[0] ## i64
  found = 0 ## i64
  attempt = 0 ## i64
  while attempt < 8 && found == 0
    m[26] += 1
    s[1856] = 0
    s[1920] = m[1]
    s[1984] = 0
    s[2048] = 0
    s[2112] = 0
    s[2176] = 0
    z = wassat_box_net_single(rng,1,0) ## i64
    z = wassat_box_net_single(rng,2,m[1])
    bucket = 0 ## i64
    while bucket < 128
      s[2560+bucket] = 0
      bucket += 1
    s[2560] = 1
    s[2688] = 0
    m[11] = 0
    m[13] = 15 + wassat_box_net_rand(rng,20)
    found = wassat_box_net_path(g,s,m,rng,stop,deadline,0)
    m[29] += m[11]
    return 0 if m[25] != 0
    attempt += 1
  return 0 if found == 0
  count = 0 ## i64
  i = 0 ## i64
  while i < n
    if wassat_box_net_has(rng,2,i) == 0
      s[2496+count] = i
      count += 1
    i += 1
  i = count-1
  while i > 0
    z = wassat_box_net_swap(s,2496+i,2496+wassat_box_net_rand(rng,i+1)) ## i64
    i -= 1
  i = 0
  while i < n
    if wassat_box_net_has(rng,1,i) == 0
      count -= 1
      s[i] = s[2496+count]
      s[64+i] = wassat_box_net_rand(rng,4)
    i += 1
  i = 0
  while i < m[12]
    u = s[1856+i] ## i64
    s[u] = s[1920+i]
    s[64+u] = (s[2048+i]-s[1984+i]+4) & 3
    i += 1
  z = wassat_box_net_inverse(s,n)
  1

-> wassat_box_net_search(g, s, m, rng, stop, deadline, max_steps) (i64[] i64[] i64[] u64[] i64[] i64 i64) i64
  n = m[0] ## i64
  fresh_period = m[30] > 0 ? m[30] : 1 ## i64
  restart = 0 ## i64
  while wassat_box_net_poll(m,stop,deadline) == 0
    m[10] += 1
    i = 0 ## i64
    while i < n
      s[i] = i
      i += 1
    i = n-1
    while i > 0
      z = wassat_box_net_swap(s,i,wassat_box_net_rand(rng,i+1)) ## i64
      i -= 1
    z = wassat_box_net_inverse(s,n)
    z = wassat_box_net_swap(s,0,s[128+m[1]])
    z = wassat_box_net_inverse(s,n)
    z = wassat_box_net_swap(s,1,s[128+m[2]])
    z = wassat_box_net_inverse(s,n)
    i = 0
    while i < n
      s[64+i] = wassat_box_net_rand(rng,4)
      i += 1
    s[64] = 0
    # A nearly connected layout can still have an incompatible global
    # topology. Default to a new anchor path instead of repeatedly mutating
    # that incumbent. Retain the previous schedule for measured controls.
    if restart % fresh_period != 0 && m[9] < 1000000
      z = wassat_box_net_copy(s,0,192,n)
      z = wassat_box_net_copy(s,64,256,n)
      k = 0 ## i64
      while k < 3+restart%12
        a = 2+wassat_box_net_rand(rng,n-2) ## i64
        b = 2+wassat_box_net_rand(rng,n-2) ## i64
        z = wassat_box_net_swap(s,a,b)
        s[64+a] = wassat_box_net_rand(rng,4)
        s[64+b] = wassat_box_net_rand(rng,4)
        k += 1
      z = wassat_box_net_inverse(s,n)
    ready = 1 ## i64
    ready = wassat_box_net_seed(g,s,m,rng,stop,deadline) if restart%fresh_period == 0 || m[9] == 1000000
    if ready != 0
      cur = wassat_box_net_evaluate(g,s,m) ## i64
      iter = 0 ## i64
      while iter < 100000
        return 0 if max_steps > 0 && m[8] >= max_steps
        return 0 if (m[8] & 8191) == 0 && wassat_box_net_poll(m,stop,deadline) != 0
        z = wassat_box_net_copy(s,320,0,n)
        z = wassat_box_net_copy(s,384,64,n)
        kind = wassat_box_net_rand(rng,10) ## i64
        moved = 1 ## i64
        if kind < 5
          u = wassat_box_net_rand(rng,n) ## i64
          d = wassat_box_net_rand(rng,4) ## i64
          x = wassat_box_net_step(0,u,0,d) ## i64
          y = wassat_box_net_step(1,s[u],s[64+u],d) ## i64
          limit = 2 << wassat_box_net_rand(rng,6) ## i64
          if wassat_box_net_rand(rng,8) == 0
            moved = wassat_box_net_block(g,s,m,rng,1,m[2],wassat_box_net_rand(rng,4),64)
          else
            moved = wassat_box_net_block(g,s,m,rng,g[x],g[y],(g[y+1]-g[x+1]+4)&3,limit)
        elsif kind < 9
          u = wassat_box_net_rand(rng,n)
          d = wassat_box_net_rand(rng,4)
          x = wassat_box_net_step(0,u,0,d)
          y = wassat_box_net_step(1,s[u],s[64+u],d)
          a = g[x]
          b = s[128+g[y]]
          if a < 2 || b < 2
            moved = 0
          else
            z = wassat_box_net_swap(s,a,b)
            s[64+a] = (g[y+1]-g[x+1]+4)&3
            s[64+b] = wassat_box_net_rand(rng,4) if a != b
        else
          a = 1+wassat_box_net_rand(rng,n-1)
          s[64+a] = wassat_box_net_rand(rng,4)
        if moved != 0
          m[27] += 1
          z = wassat_box_net_inverse(s,n)
          next_score = wassat_box_net_evaluate(g,s,m) ## i64
          temp = ~0.4 + ~8.0 * (~1.0-iter / ~100000.0) ## f64
          accept = next_score <= cur
          unless accept
            trial = wassat_box_net_rand(rng,1000000) / ~1000000.0 ## f64
            accept = trial < Math.exp((cur-next_score) / temp)
          if accept
            cur = next_score
            if cur < m[9]
              m[9] = cur
              z = wassat_box_net_copy(s,192,0,n)
              z = wassat_box_net_copy(s,256,64,n)
            if m[18] == 1 && m[19] == 0 && m[20] == 0 && m[21] == 0 && m[22] == 0
              z = wassat_box_net_copy(s,192,0,n)
              z = wassat_box_net_copy(s,256,64,n)
              m[24] += 1
              m[8] += 1
              return 1
          else
            z = wassat_box_net_copy(s,0,320,n)
            z = wassat_box_net_copy(s,64,384,n)
            z = wassat_box_net_inverse(s,n)
        else
          m[28] += 1
        iter += 1
        m[8] += 1
    restart += 1
  0
