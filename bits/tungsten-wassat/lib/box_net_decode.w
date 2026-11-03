# Recover canonical common-net clauses, without names or box dimensions.
# Recognition only proposes a model space; it never proves SAT or UNSAT.
use box_net_walk

-> wassat_box_net_decode_poll(dm, stop, deadline) (i64[] i64[] i64) i64
  dm[6] += 1
  if wassat_stop_load(stop) != 0
    dm[7] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    dm[7] = 2
  dm[7]

-> wassat_box_net_decode_pair(head, link, other, a, b) (i64[] i64[] i64[] i64 i64) i64
  e = head[a] ## i64
  while e != 0
    return 1 if other[e-1] == b
    e = link[e-1]
  0

-> wassat_box_net_decode_dir(r, d) (i64 i64) i64
  return d if r == 0
  return d == 0 ? 3 : (d == 1 ? 2 : (d == 2 ? 0 : 1)) if r == 1
  return d ^ 1 if r == 2
  d == 0 ? 2 : (d == 1 ? 3 : (d == 2 ? 1 : 0))

-> wassat_box_net_decode_map(lits, offs, lens, nv, nc, n, mapvars, mapidx, units, head, link, other, dm, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  wide = 0 ## i64
  bins = 0 ## i64
  ci = 0 ## i64
  row_seen = i64[n]
  col_seen = i64[n]
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_box_net_decode_poll(dm,stop,deadline) != 0
    dm[1] += 1
    off = offs[ci] ## i64
    k = lens[ci] ## i64
    if k == 1
      v = lits[off] ## i64
      units[v] = 1 if v > 0
    elsif k == 2 && lits[off] < 0 && lits[off+1] < 0
      a = -lits[off] ## i64
      b = -lits[off+1] ## i64
      return 0 if bins+2 > link.size
      other[bins] = b
      link[bins] = head[a]
      head[a] = bins+1
      other[bins+1] = a
      link[bins+1] = head[b]
      head[b] = bins+2
      bins += 2
    elsif k > 4
      return 0 if k != n || wide >= 2*n
      i = 0 ## i64
      col = -1 ## i64
      while i < n
        v = lits[off+i]
        return 0 if v <= 0 || v > nv
        if wide < n
          return 0 if mapidx[v] != 0
          mapvars[wide*n+i] = v
          mapidx[v] = wide*n+i+1
        else
          idx = mapidx[v]-1 ## i64
          return 0 if idx < 0
          c = idx % n ## i64
          row = idx / n ## i64
          col = c if col < 0
          return 0 if col != c || row_seen[row] == wide+1
          row_seen[row] = wide+1
        i += 1
      if wide >= n
        return 0 if col_seen[col] != 0
        col_seen[col] = 1
      wide += 1
    ci += 1
  dm[2] = bins / 2
  wide == 2*n ? 1 : 0

-> wassat_box_net_decode_ori(lits, offs, lens, nc, n, mapidx, head, link, other, orivars, oriidx, dm, stop, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  groups = 0 ## i64
  ci = 0 ## i64
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_box_net_decode_poll(dm,stop,deadline) != 0
    dm[1] += 1
    if lens[ci] == 4
      off = offs[ci] ## i64
      good = 1 ## i64
      a = 0 ## i64
      while a < 4 && good != 0
        v = lits[off+a] ## i64
        good = 0 if v <= 0
        b = 0 ## i64
        while b < a && good != 0
          good = wassat_box_net_decode_pair(head,link,other,v,lits[off+b])
          b += 1
        a += 1
      if good != 0
        return 0 if groups >= 2*n
        a = 0
        while a < 4
          v = lits[off+a]
          return 0 if oriidx[v] != 0 || mapidx[v] != 0
          oriidx[v] = groups*4+a+1
          orivars[groups*4+a] = v
          a += 1
        groups += 1
    ci += 1
  dm[3] = groups
  groups == 2*n ? 1 : 0

-> wassat_box_net_decode_rot(lits, offs, lens, nc, n, mapidx, oriidx, relvars, relidx, dm, stop, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  masks = i64[n*n]
  ci = 0 ## i64
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_box_net_decode_poll(dm,stop,deadline) != 0
    dm[1] += 1
    if lens[ci] == 4
      off = offs[ci] ## i64
      maps = 0 ## i64
      oris = 0 ## i64
      positives = 0 ## i64
      mv = 0 ## i64
      first = 0 ## i64
      second = 0 ## i64
      pv = 0 ## i64
      k = 0 ## i64
      while k < 4
        v = lits[off+k] ## i64
        if v > 0
          positives += 1
          pv = v
        else
          vv = -v ## i64
          if mapidx[vv] != 0
            maps += 1
            mv = mapidx[vv]-1
          elsif oriidx[vv] != 0
            first = second
            second = oriidx[vv]-1
            oris += 1
        k += 1
      if maps == 1 && oris == 2 && positives == 1
        if first > second
          tmp = first ## i64
          first = second
          second = tmp
        i = mv % n ## i64
        j = mv / n ## i64
        return 0 if first / 4 != i || second / 4 != n+j
        r = (second-first+4) & 3 ## i64
        ri = i*4+r ## i64
        return 0 if mapidx[pv] != 0 || oriidx[pv] != 0
        return 0 if relvars[ri] != 0 && relvars[ri] != pv
        return 0 if relidx[pv] != 0 && relidx[pv] != ri+1
        relvars[ri] = pv
        relidx[pv] = ri+1
        bit = 1 << (r*4+(first & 3)) ## i64
        return 0 if (masks[mv] & bit) != 0
        masks[mv] |= bit
        dm[4] += 1
    ci += 1
  i = 0
  while i < n*n
    return 0 if masks[i] != 65535
    i += 1
  1

-> wassat_box_net_decode_steps(lits, offs, lens, nv, nc, n, mapidx, oriidx, relidx, cutidx, cutvars, g, m, dm, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  counts = i64[512]
  ci = 0 ## i64
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_box_net_decode_poll(dm,stop,deadline) != 0
    dm[1] += 1
    if lens[ci] == 3
      off = offs[ci] ## i64
      negs = 0 ## i64
      poss = 0 ## i64
      cuts = 0 ## i64
      a = 0 ## i64
      b = 0 ## i64
      cv = 0 ## i64
      k = 0 ## i64
      while k < 3
        v = lits[off+k] ## i64
        if v < 0 && oriidx[-v] != 0
          negs += 1
          a = oriidx[-v]-1
        elsif v > 0 && oriidx[v] != 0
          poss += 1
          b = oriidx[v]-1
        elsif v > 0
          cuts += 1
          cv = v
        k += 1
      if negs == 1 && poss == 1 && cuts == 1
        box = a / (4*n) ## i64
        return 0 if b / (4*n) != box || mapidx[cv] != 0 || relidx[cv] != 0
        return 0 if cutidx[cv] != 0 && cutidx[cv] != box+1
        cutidx[cv] = box+1
        d = counts[a] ## i64
        return 0 if d >= 4
        at = wassat_box_net_step(box,(a / 4) % n,a & 3,d) ## i64
        g[at] = (b / 4) % n
        g[at+1] = b & 3
        g[at+2] = cv
        counts[a] += 1
    ci += 1
  i = 0 ## i64
  while i < 8*n
    return 0 if counts[i] != 4
    i += 1
  ne0 = 0 ## i64
  ne1 = 0 ## i64
  v = 1
  while v <= nv
    box = cutidx[v]-1
    if box >= 0
      e = box == 0 ? ne0 : ne1 ## i64
      return 0 if e >= 2*n
      cutvars[box*128+e] = v
      cutidx[v] = box*128+e+1
      if box == 0
        ne0 += 1
      else
        ne1 += 1
    v += 1
  return 0 if ne0 != 2*n || ne1 != 2*n
  box = 0
  while box < 2
    i = 0
    while i < n
      r = 0 ## i64
      while r < 4
        d = 0
        while d < 4
          at = wassat_box_net_step(box,i,r,d)
          g[at+2] = (cutidx[g[at+2]]-1) % 128
          d += 1
        r += 1
      i += 1
    box += 1
  box = 0
  while box < 2
    i = 0
    while i < n
      r = 0
      while r < 4
        d = 0
        while d < 4
          at = wassat_box_net_step(box,i,r,d)
          base = wassat_box_net_step(box,i,0,wassat_box_net_decode_dir(r,d)) ## i64
          expected = (g[base+1]+r) & 3 ## i64
          return 0 if g[at] != g[base] || g[at+1] != expected || g[at+2] != g[base+2]
          back = wassat_box_net_step(box,g[at],g[at+1],d ^ 1) ## i64
          return 0 if g[back] != i || g[back+1] != r || g[back+2] != g[at+2]
          d += 1
        r += 1
      i += 1
    box += 1
  1

-> wassat_box_net_decode_faces(lits, offs, lens, nc, n, cutidx, g, m, dm, stop, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64) i64
  quad_masks = i64[128]
  edges = i64[4]
  ci = 0 ## i64
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_box_net_decode_poll(dm,stop,deadline) != 0
    dm[1] += 1
    size = lens[ci] ## i64
    if size == 3 || size == 4
      off = offs[ci] ## i64
      box = -1 ## i64
      good = 1 ## i64
      negatives = 0 ## i64
      negedge = -1 ## i64
      k = 0 ## i64
      while k < size && good != 0
        v = lits[off+k] ## i64
        vv = v < 0 ? -v : v ## i64
        idx = cutidx[vv]-1 ## i64
        if idx < 0
          good = 0
        else
          b = idx / 128 ## i64
          box = b if box < 0
          good = 0 if b != box
          edges[k] = idx % 128
          if v < 0
            negatives += 1
            negedge = edges[k]
        k += 1
      if good != 0
        a = 1 ## i64
        while a < size
          b = a
          while b > 0 && edges[b-1] > edges[b]
            tmp = edges[b] ## i64
            edges[b] = edges[b-1]
            edges[b-1] = tmp
            b -= 1
          a += 1
        a = 1
        while a < size
          return 0 if edges[a] == edges[a-1]
          a += 1
        if size == 3 && negatives == 0
          count = m[5+box] ## i64
          return 0 if count >= 8
          k = 0
          while k < 3
            g[6656+box*24+count*3+k] = edges[k]
            k += 1
          m[5+box] += 1
        elsif size == 4 && negatives == 1
          q = 0 ## i64
          found = -1 ## i64
          while q < m[3+box] && found < 0
            base = 6144+box*256+q*4 ## i64
            same = 1 ## i64
            k = 0
            while k < 4
              same = 0 if g[base+k] != edges[k]
              k += 1
            found = q if same != 0
            q += 1
          if found < 0
            found = m[3+box]
            return 0 if found >= n-6
            m[3+box] += 1
            k = 0
            while k < 4
              g[6144+box*256+found*4+k] = edges[k]
              k += 1
          k = 0
          while edges[k] != negedge
            k += 1
          bit = 1 << k ## i64
          return 0 if (quad_masks[box*64+found] & bit) != 0
          quad_masks[box*64+found] |= bit
    ci += 1
  box = 0
  while box < 2
    return 0 if m[5+box] != 8 || m[3+box] != n-6
    q = 0
    while q < n-6
      return 0 if quad_masks[box*64+q] != 15
      q += 1
    box += 1
  1

-> wassat_box_net_decode_coherence(lits, offs, lens, nc, n, mapvars, mapidx, relidx, cutidx, g, dm, stop, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  masks = i64[4*n*n]
  ci = 0 ## i64
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_box_net_decode_poll(dm,stop,deadline) != 0
    dm[1] += 1
    if lens[ci] == 4
      off = offs[ci] ## i64
      maps = 0 ## i64
      rels = 0 ## i64
      mv = 0 ## i64
      rv = 0 ## i64
      ml = 0 ## i64
      rl = 0 ## i64
      k = 0 ## i64
      while k < 4
        v = lits[off+k] ## i64
        if v < 0
          if mapidx[-v] != 0
            maps += 1
            mv = mapidx[-v]-1
            ml = v
          elsif relidx[-v] != 0
            rels += 1
            rv = relidx[-v]-1
            rl = v
        k += 1
      if maps == 1 && rels == 1
        i = mv % n ## i64
        j = mv / n ## i64
        r = rv & 3 ## i64
        return 0 if rv / 4 != i
        ec = 0 ## i64
        el = 0 ## i64
        other = 0 ## i64
        k = 0
        while k < 4
          v = lits[off+k]
          if v != ml && v != rl
            vv = v < 0 ? -v : v ## i64
            if cutidx[vv] > 0 && cutidx[vv] <= 128
              ec += 1
              el = v
            else
              other = v
          k += 1
        return 0 if ec != 1 || other == 0
        vv = el < 0 ? -el : el
        e = cutidx[vv]-1 ## i64
        d = 0 ## i64
        found = -1 ## i64
        while d < 4
          if g[wassat_box_net_step(0,i,0,d)+2] == e
            return 0 if found >= 0
            found = d
          d += 1
        return 0 if found < 0
        a = wassat_box_net_step(0,i,0,found) ## i64
        b = wassat_box_net_step(1,j,r,found) ## i64
        kind = 0 ## i64
        if other > 0 && mapidx[other] != 0
          return 0 if el < 0 || other != mapvars[g[b]*n+g[a]]
        else
          ov = other < 0 ? -other : other ## i64
          return 0 if cutidx[ov] != 129+g[b+2] || (el > 0) == (other > 0)
          kind = el > 0 ? 1 : 2
        bit = 1 << (found*3+kind) ## i64
        idx = mv*4+r ## i64
        return 0 if (masks[idx] & bit) != 0
        masks[idx] |= bit
        dm[5] += 1
    ci += 1
  k = 0
  while k < 4*n*n
    return 0 if masks[k] != 4095
    k += 1
  1

-> wassat_box_net_decode_anchors(n, mapvars, orivars, relvars, units, g, m) (i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  count = 0 ## i64
  fixed = 0 ## i64
  a0 = -1 ## i64
  a1 = -1 ## i64
  b0 = -1 ## i64
  b1 = -1 ## i64
  j = 0 ## i64
  while j < n
    i = 0 ## i64
    while i < n
      if units[mapvars[j*n+i]] != 0
        count += 1
        if units[orivars[4*i]] != 0 && units[orivars[4*(n+j)]] != 0
          a0 = i
          b0 = j
          fixed += 1
        else
          a1 = i
          b1 = j
      i += 1
    j += 1
  return 0 if count != 2 || fixed != 1 || a0 < 0 || a1 < 0 || a0 == a1 || b0 == b1
  m[1] = b0
  m[2] = b1
  order = i64[n]
  inverse = i64[n]
  order[0] = a0
  order[1] = a1
  at = 2 ## i64
  i = 0
  while i < n
    if i != a0 && i != a1
      order[at] = i
      at += 1
    i += 1
  i = 0
  while i < n
    inverse[order[i]] = i
    i += 1
  previous = i64[3072]
  k = 0 ## i64
  while k < n*48
    previous[k] = g[k]
    k += 1
  i = 0
  while i < n
    k = 0
    while k < 48
      g[i*48+k] = previous[order[i]*48+k]
      g[i*48+k] = inverse[g[i*48+k]] if k % 3 == 0
      k += 1
    i += 1
  scratch = i64[256]
  j = 0
  while j < n
    i = 0
    while i < n
      scratch[i] = mapvars[j*n+order[i]]
      i += 1
    i = 0
    while i < n
      mapvars[j*n+i] = scratch[i]
      i += 1
    j += 1
  k = 0
  while k < n*4
    scratch[k] = relvars[order[k / 4]*4+(k & 3)]
    k += 1
  k = 0
  while k < n*4
    relvars[k] = scratch[k]
    k += 1
  1

-> wassat_box_net_decode(formula, stop, deadline, dm)
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 64 || nv > 40000 || nc < 1 || nc > 500000
  lits = formula["flat_lits"]
  offs = formula["flat_offs"]
  lens = formula["flat_lens"]
  n = 0
  negatives = 0
  ci = 0
  while ci < nc
    return nil if (ci & 255) == 0 && wassat_box_net_decode_poll(dm,stop,deadline) != 0
    dm[1] += 1
    k = lens[ci]
    return nil if k < 1 || k > 64
    if k > 4
      n = k if n == 0
      return nil if n != k
    off = offs[ci]
    negatives += 1 if k == 2 && lits[off] < 0 && lits[off+1] < 0
    ci += 1
  return nil if n < 8 || n > 64 || nv < n*n || nc < 64*n*n
  mapvars = i64[n*n]
  mapidx = i64[nv+1]
  oriidx = i64[nv+1]
  orivars = i64[8*n]
  relidx = i64[nv+1]
  relvars = i64[4*n]
  cutidx = i64[nv+1]
  cutvars = i64[256]
  units = i64[nv+1]
  head = i64[nv+1]
  link = i64[2*negatives]
  other = i64[2*negatives]
  g = i64[8192]
  m = i64[32]
  m[0] = n
  m[9] = 1000000
  dm[8] = 1
  return nil if wassat_box_net_decode_map(lits,offs,lens,nv,nc,n,mapvars,mapidx,units,head,link,other,dm,stop,deadline) == 0
  dm[8] = 2
  return nil if wassat_box_net_decode_ori(lits,offs,lens,nc,n,mapidx,head,link,other,orivars,oriidx,dm,stop,deadline) == 0
  dm[8] = 3
  return nil if wassat_box_net_decode_rot(lits,offs,lens,nc,n,mapidx,oriidx,relvars,relidx,dm,stop,deadline) == 0
  dm[8] = 4
  return nil if wassat_box_net_decode_steps(lits,offs,lens,nv,nc,n,mapidx,oriidx,relidx,cutidx,cutvars,g,m,dm,stop,deadline) == 0
  dm[8] = 5
  return nil if wassat_box_net_decode_faces(lits,offs,lens,nc,n,cutidx,g,m,dm,stop,deadline) == 0
  dm[8] = 6
  return nil if wassat_box_net_decode_coherence(lits,offs,lens,nc,n,mapvars,mapidx,relidx,cutidx,g,dm,stop,deadline) == 0
  dm[8] = 7
  return nil if wassat_box_net_decode_anchors(n,mapvars,orivars,relvars,units,g,m) == 0
  dm[0] = 1
  {"geometry": g, "state": m, "mapping": mapvars, "rotation": relvars, "decode_meta": dm}

-> wassat_box_net_replay(lits, offs, lens, nv, nc, values, p, stop, deadline) (i64[] i64[] i64[] i64 i64 i8[] i64[] i64[] i64) i64
  ci = 0 ## i64
  while ci < nc
    if (ci & 255) == 0
      return 0 if wassat_stop_load(stop) != 0 || clock_ms() >= deadline
    off = offs[ci] ## i64
    k = 0 ## i64
    satisfied = 0 ## i64
    while k < lens[ci] && satisfied == 0
      lit = lits[off+k] ## i64
      v = lit < 0 ? -lit : lit ## i64
      return 0 if v < 1 || v > nv
      satisfied = 1 if (lit > 0 && values[v] == 1) || (lit < 0 && values[v] == 0)
      p[11] += 1
      k += 1
    return 0 if satisfied == 0
    p[10] += 1
    ci += 1
  1

