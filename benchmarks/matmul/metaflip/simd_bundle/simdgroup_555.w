# Cooperative Metal flip-graph walker for <5,5,5> over GF(2).
#
# Unlike flipgraph_gpu_cal2zone.w (one independent scheme per GPU lane), this
# kernel assigns one complete scheme to one 32-lane Apple SIMDgroup.  Partner,
# zero-term, touched-duplicate, density, and copy scans are striped over the 32
# lanes and combined with simd_min/simd_sum.  The companion generator rewrites
# the mask width and compile-time capacities for 6x6.
#
# This file is deliberately a standalone benchmark, not a fleet coordinator.
# It writes its independently full-verified best scheme to argv[1] and prints
# enough counters to compare aggregate throughput and per-trajectory latency.

## i32[]: work_us
## i32[]: work_vs
## i32[]: work_ws
## i32[]: best_us
## i32[]: best_vs
## i32[]: best_ws
## i32[]: st
## i32[]: seed_us
## i32[]: seed_vs
## i32[]: seed_ws
## i32[]: params
@gpu fn flipwalk_simd(work_us, work_vs, work_ws, best_us, best_vs, best_ws, st, seed_us, seed_vs, seed_ws, params)
  gid = gpu.threadgroup_position_in_grid.x ## i32
  lane = gpu.thread_index_in_simdgroup ## i32
  nterms = params[0] ## i32
  cap = params[1] ## i32
  steps = params[2] ## i32
  doinit = params[3] ## i32
  margin = params[4] ## i32
  seedden = params[5] ## i32
  mode = params[6] ## i32
  base = gid * cap ## i32
  sb = gid * 8 ## i32
  sus = gpu.shared_i32(144)
  svs = gpu.shared_i32(144)
  sws = gpu.shared_i32(144)
  schanged = gpu.shared_i32(6)
  # Hash mode uses one compact head table per factor axis and one next link per
  # (axis, term).  Scan mode leaves these untouched; keeping both modes in one
  # kernel makes the A/B use identical dispatch and state machinery.
  heads = gpu.shared_i32(768)
  nexts = gpu.shared_i32(432)

  i = lane ## i32
  rank = 0 ## i32
  best = 0 ## i32
  state = 0 ## i32
  bestden = 0 ## i32
  attempts = 0 ## i32
  partners = 0 ## i32
  captures = 0 ## i32
  step = 0 ## i32
  roll = 0 ## i32
  didplus = 0 ## i32
  pt = 0 ## i32
  part = 0 ## i32
  fi = 0 ## i32
  fj = -1 ## i32
  axis = 0 ## i32
  off = 0 ## i32
  cand = 0 ## i32
  scan = 0 ## i32
  localmin = 0 ## i32
  bestdist = 0 ## i32
  t = 0 ## i32
  m1 = 0 ## i32
  m2 = 0 ## i32
  zi = 0 ## i32
  hi = 0 ## i32
  lo = 0 ## i32
  last = 0 ## i32
  have1 = 0 ## i32
  have2 = 0 ## i32
  cu1 = 0 ## i32
  cv1 = 0 ## i32
  cw1 = 0 ## i32
  cu2 = 0 ## i32
  cv2 = 0 ## i32
  cw2 = 0 ## i32
  localden = 0 ## i32
  dsum = 0 ## i32
  px = 0 ## i32
  capture = 0 ## i32
  hashedrank = 0 ## i32
  buildaxis = 0 ## i32
  update = 0 ## i32
  updidx = 0 ## i32
  updaxis = 0 ## i32
  hashslot = 0 ## i32
  headslot = 0 ## i32
  cur = 0 ## i32
  prev = 0 ## i32
  nxt = 0 ## i32
  oldfactor = 0 ## i32

  if doinit == 1
    i = lane
    while i < nterms
      sus[i] = seed_us[i]
      svs[i] = seed_vs[i]
      sws[i] = seed_ws[i]
      best_us[base + i] = seed_us[i]
      best_vs[base + i] = seed_vs[i]
      best_ws[base + i] = seed_ws[i]
      i = i + 32
    if lane == 0
      st[sb] = nterms
      st[sb + 1] = nterms
      st[sb + 2] = gid * 9973 + 12345
      st[sb + 3] = seedden
      st[sb + 4] = 0
      st[sb + 5] = 0
      st[sb + 6] = 0
      st[sb + 7] = 0
  if doinit == 0
    if lane == 0
      rank = st[sb]
    rank = simd_broadcast_first(rank)
    i = lane
    while i < rank
      sus[i] = work_us[base + i]
      svs[i] = work_vs[base + i]
      sws[i] = work_ws[base + i]
      i = i + 32
  threadgroup_barrier()

  if lane == 0
    rank = st[sb]
    best = st[sb + 1]
    state = st[sb + 2]
    bestden = st[sb + 3]
    attempts = st[sb + 4]
    partners = st[sb + 5]
    captures = st[sb + 6]
  rank = simd_broadcast_first(rank)
  best = simd_broadcast_first(best)
  state = simd_broadcast_first(state)
  bestden = simd_broadcast_first(bestden)
  attempts = simd_broadcast_first(attempts)
  partners = simd_broadcast_first(partners)
  captures = simd_broadcast_first(captures)

  # Build hash chains once per dispatch.  Only rank-changing cancellation
  # rebuilds them later; ordinary flips and splits update two/four links in O(1).
  if mode == 1
    i = lane
    while i < 768
      heads[i] = -1
      i = i + 32
    threadgroup_barrier()
    if lane == 0
      buildaxis = 0
      while buildaxis < 3
        i = 0
        while i < rank
          oldfactor = sus[i]
          if buildaxis == 1
            oldfactor = svs[i]
          if buildaxis == 2
            oldfactor = sws[i]
          hashslot = (oldfactor ^ (oldfactor >> 11) ^ (oldfactor >> 23)) & 255
          headslot = buildaxis * 256 + hashslot
          nexts[buildaxis * cap + i] = heads[headslot]
          heads[headslot] = i
          i = i + 1
        buildaxis = buildaxis + 1
    threadgroup_barrier()

  step = 0
  while step < steps
    # Lane zero owns the RNG and the two O(1) writes.  All search work below
    # is cooperative; broadcasting keeps every lane on the same trajectory.
    if lane == 0
      attempts = attempts + 1
      state = state * 1103515245 + 12345
      roll = ((state % 6) + 6) % 6
      didplus = 0
      have1 = 0
      have2 = 0
      if roll == 0
        if rank < best + margin
          if rank < cap
            state = state * 1103515245 + 12345
            pt = ((state % rank) + rank) % rank
            state = state * 1103515245 + 12345
            part = (((state % 33554431) + 33554431) % 33554431) + 1
            state = state * 1103515245 + 12345
            axis = ((state % 3) + 3) % 3
            oldfactor = sus[pt]
            if axis == 1
              oldfactor = svs[pt]
            if axis == 2
              oldfactor = sws[pt]
            if part != oldfactor
              # Unlink the factor being split from its old axis bucket.
              if mode == 1
                hashslot = (oldfactor ^ (oldfactor >> 11) ^ (oldfactor >> 23)) & 255
                headslot = axis * 256 + hashslot
                cur = heads[headslot]
                prev = -1
                while cur >= 0
                  nxt = nexts[axis * cap + cur]
                  if cur == pt
                    if prev < 0
                      heads[headslot] = nxt
                    if prev >= 0
                      nexts[axis * cap + prev] = nxt
                    cur = -1
                  if cur >= 0
                    prev = cur
                    cur = nxt
              if axis == 0
                sus[rank] = sus[pt] ^ part
                svs[rank] = svs[pt]
                sws[rank] = sws[pt]
                sus[pt] = part
              if axis == 1
                svs[rank] = svs[pt] ^ part
                sus[rank] = sus[pt]
                sws[rank] = sws[pt]
                svs[pt] = part
              if axis == 2
                sws[rank] = sws[pt] ^ part
                sus[rank] = sus[pt]
                svs[rank] = svs[pt]
                sws[pt] = part
              # Reinsert the changed old slot and insert the new slot on all
              # three axes.  These are the only links a split changes.
              if mode == 1
                oldfactor = sus[pt]
                if axis == 1
                  oldfactor = svs[pt]
                if axis == 2
                  oldfactor = sws[pt]
                hashslot = (oldfactor ^ (oldfactor >> 11) ^ (oldfactor >> 23)) & 255
                headslot = axis * 256 + hashslot
                nexts[axis * cap + pt] = heads[headslot]
                heads[headslot] = pt
                buildaxis = 0
                while buildaxis < 3
                  oldfactor = sus[rank]
                  if buildaxis == 1
                    oldfactor = svs[rank]
                  if buildaxis == 2
                    oldfactor = sws[rank]
                  hashslot = (oldfactor ^ (oldfactor >> 11) ^ (oldfactor >> 23)) & 255
                  headslot = buildaxis * 256 + hashslot
                  nexts[buildaxis * cap + rank] = heads[headslot]
                  heads[headslot] = rank
                  buildaxis = buildaxis + 1
              cu1 = sus[pt]
              cv1 = svs[pt]
              cw1 = sws[pt]
              cu2 = sus[rank]
              cv2 = svs[rank]
              cw2 = sws[rank]
              rank = rank + 1
              didplus = 1
            if didplus == 1
              have1 = 1
              have2 = 1
      if didplus == 0
        state = state * 1103515245 + 12345
        fi = ((state % rank) + rank) % rank
        state = state * 1103515245 + 12345
        axis = ((state % 3) + 3) % 3
        state = state * 1103515245 + 12345
        off = ((state % rank) + rank) % rank
    rank = simd_broadcast_first(rank)
    best = simd_broadcast_first(best)
    state = simd_broadcast_first(state)
    attempts = simd_broadcast_first(attempts)
    roll = simd_broadcast_first(roll)
    didplus = simd_broadcast_first(didplus)
    fi = simd_broadcast_first(fi)
    axis = simd_broadcast_first(axis)
    off = simd_broadcast_first(off)
    threadgroup_barrier()

    # Rotated parallel partner scan.  The reduced distance preserves the
    # first-found ordering of the scalar walker, not merely any matching term.
    if didplus == 0
      localmin = 2147483647
      fj = -1
      if mode == 0
        scan = lane
        while scan < rank
          cand = (off + scan) % rank
          if cand != fi
            if axis == 0
              if sus[cand] == sus[fi]
                if scan < localmin
                  localmin = scan
            if axis == 1
              if svs[cand] == svs[fi]
                if scan < localmin
                  localmin = scan
            if axis == 2
              if sws[cand] == sws[fi]
                if scan < localmin
                  localmin = scan
          scan = scan + 32
        bestdist = simd_min(localmin)
        if bestdist < 2147483647
          fj = (off + bestdist) % rank
      if mode == 1
        if lane == 0
          oldfactor = sus[fi]
          if axis == 1
            oldfactor = svs[fi]
          if axis == 2
            oldfactor = sws[fi]
          hashslot = (oldfactor ^ (oldfactor >> 11) ^ (oldfactor >> 23)) & 255
          cur = heads[axis * 256 + hashslot]
          while cur >= 0
            if cur != fi
              cand = 0
              if axis == 0
                if sus[cur] == oldfactor
                  cand = 1
              if axis == 1
                if svs[cur] == oldfactor
                  cand = 1
              if axis == 2
                if sws[cur] == oldfactor
                  cand = 1
              if cand == 1
                scan = (cur - off + rank) % rank
                if scan < localmin
                  localmin = scan
                  fj = cur
            cur = nexts[axis * cap + cur]
        fj = simd_broadcast_first(fj)
      if lane == 0
        if fj >= 0
          partners = partners + 1
          # Unlink the two factors that this flip changes.
          if mode == 1
            update = 0
            while update < 2
              updidx = fi
              updaxis = 2
              if update == 1
                updidx = fj
                updaxis = 1
              if axis == 1
                if update == 1
                  updaxis = 0
              if axis == 2
                if update == 0
                  updaxis = 1
                if update == 1
                  updaxis = 0
              oldfactor = sus[updidx]
              if updaxis == 1
                oldfactor = svs[updidx]
              if updaxis == 2
                oldfactor = sws[updidx]
              hashslot = (oldfactor ^ (oldfactor >> 11) ^ (oldfactor >> 23)) & 255
              headslot = updaxis * 256 + hashslot
              cur = heads[headslot]
              prev = -1
              while cur >= 0
                nxt = nexts[updaxis * cap + cur]
                if cur == updidx
                  if prev < 0
                    heads[headslot] = nxt
                  if prev >= 0
                    nexts[updaxis * cap + prev] = nxt
                  cur = -1
                if cur >= 0
                  prev = cur
                  cur = nxt
              update = update + 1
          if axis == 0
            sws[fi] = sws[fi] ^ sws[fj]
            svs[fj] = svs[fi] ^ svs[fj]
          if axis == 1
            sws[fi] = sws[fi] ^ sws[fj]
            sus[fj] = sus[fi] ^ sus[fj]
          if axis == 2
            svs[fi] = svs[fi] ^ svs[fj]
            sus[fj] = sus[fi] ^ sus[fj]
          if mode == 1
            update = 0
            while update < 2
              updidx = fi
              updaxis = 2
              if update == 1
                updidx = fj
                updaxis = 1
              if axis == 1
                if update == 1
                  updaxis = 0
              if axis == 2
                if update == 0
                  updaxis = 1
                if update == 1
                  updaxis = 0
              oldfactor = sus[updidx]
              if updaxis == 1
                oldfactor = svs[updidx]
              if updaxis == 2
                oldfactor = sws[updidx]
              hashslot = (oldfactor ^ (oldfactor >> 11) ^ (oldfactor >> 23)) & 255
              headslot = updaxis * 256 + hashslot
              nexts[updaxis * cap + updidx] = heads[headslot]
              heads[headslot] = updidx
              update = update + 1
          cu1 = sus[fi]
          cv1 = svs[fi]
          cw1 = sws[fi]
          cu2 = sus[fj]
          cv2 = svs[fj]
          cw2 = sws[fj]
          have1 = 1
          have2 = 1
    if lane == 0
      schanged[0] = cu1
      schanged[1] = cv1
      schanged[2] = cw1
      schanged[3] = cu2
      schanged[4] = cv2
      schanged[5] = cw2
    partners = simd_broadcast_first(partners)
    have1 = simd_broadcast_first(have1)
    have2 = simd_broadcast_first(have2)
    threadgroup_barrier()
    cu1 = schanged[0]
    cv1 = schanged[1]
    cw1 = schanged[2]
    cu2 = schanged[3]
    cv2 = schanged[4]
    cw2 = schanged[5]
    hashedrank = rank
    hashedrank = simd_broadcast_first(hashedrank)

    # A flip/split can only introduce duplicates having one of its two changed
    # triples.  Find the first two occurrences of each triple cooperatively and
    # cancel them.  This is O(rank/32), not a periodic O(rank^2) sweep.
    if have1 == 1
      if cu1 != 0
        if cv1 != 0
          if cw1 != 0
            localmin = cap
            t = lane
            while t < rank
              if sus[t] == cu1
                if svs[t] == cv1
                  if sws[t] == cw1
                    if t < localmin
                      localmin = t
              t = t + 32
            m1 = simd_min(localmin)
            localmin = cap
            t = lane
            while t < rank
              if t != m1
                if sus[t] == cu1
                  if svs[t] == cv1
                    if sws[t] == cw1
                      if t < localmin
                        localmin = t
              t = t + 32
            m2 = simd_min(localmin)
            if lane == 0
              if m2 < rank
                hi = m1
                lo = m2
                if lo > hi
                  hi = m2
                  lo = m1
                last = rank - 1
                if hi != last
                  sus[hi] = sus[last]
                  svs[hi] = svs[last]
                  sws[hi] = sws[last]
                rank = rank - 1
                last = rank - 1
                if lo != last
                  sus[lo] = sus[last]
                  svs[lo] = svs[last]
                  sws[lo] = sws[last]
                rank = rank - 1
            rank = simd_broadcast_first(rank)
            threadgroup_barrier()

    if have2 == 1
      if cu2 != 0
        if cv2 != 0
          if cw2 != 0
            localmin = cap
            t = lane
            while t < rank
              if sus[t] == cu2
                if svs[t] == cv2
                  if sws[t] == cw2
                    if t < localmin
                      localmin = t
              t = t + 32
            m1 = simd_min(localmin)
            localmin = cap
            t = lane
            while t < rank
              if t != m1
                if sus[t] == cu2
                  if svs[t] == cv2
                    if sws[t] == cw2
                      if t < localmin
                        localmin = t
              t = t + 32
            m2 = simd_min(localmin)
            if lane == 0
              if m2 < rank
                hi = m1
                lo = m2
                if lo > hi
                  hi = m2
                  lo = m1
                last = rank - 1
                if hi != last
                  sus[hi] = sus[last]
                  svs[hi] = svs[last]
                  sws[hi] = sws[last]
                rank = rank - 1
                last = rank - 1
                if lo != last
                  sus[lo] = sus[last]
                  svs[lo] = svs[last]
                  sws[lo] = sws[last]
                rank = rank - 1
            rank = simd_broadcast_first(rank)
            threadgroup_barrier()

    # Remove every newly created zero term.  The loop normally executes zero
    # or one times, but retaining the fixed point makes cancellation robust.
    zi = 0
    while zi < rank
      localmin = cap
      t = lane
      while t < rank
        if sus[t] == 0
          if t < localmin
            localmin = t
        if svs[t] == 0
          if t < localmin
            localmin = t
        if sws[t] == 0
          if t < localmin
            localmin = t
        t = t + 32
      zi = simd_min(localmin)
      if lane == 0
        if zi < rank
          last = rank - 1
          if zi != last
            sus[zi] = sus[last]
            svs[zi] = svs[last]
            sws[zi] = sws[last]
          rank = rank - 1
      rank = simd_broadcast_first(rank)
      threadgroup_barrier()

    # Swapping terms during zero/duplicate cancellation invalidates term-index
    # links.  Such a swap is also a rank change, so rebuild only on descents;
    # the overwhelmingly common same-rank step retains O(bucket length) lookup.
    if mode == 1
      if rank != hashedrank
        i = lane
        while i < 768
          heads[i] = -1
          i = i + 32
        threadgroup_barrier()
        if lane == 0
          buildaxis = 0
          while buildaxis < 3
            i = 0
            while i < rank
              oldfactor = sus[i]
              if buildaxis == 1
                oldfactor = svs[i]
              if buildaxis == 2
                oldfactor = sws[i]
              hashslot = (oldfactor ^ (oldfactor >> 11) ^ (oldfactor >> 23)) & 255
              headslot = buildaxis * 256 + hashslot
              nexts[buildaxis * cap + i] = heads[headslot]
              heads[headslot] = i
              i = i + 1
            buildaxis = buildaxis + 1
        threadgroup_barrier()

    # Rank always dominates density; equal-rank density is sampled every 64
    # steps.  Popcount work is naturally distributed by term.
    capture = 0
    if rank < best
      capture = 1
    if rank == best
      if (step % 64) == 0
        capture = 1
    if capture == 1
      localden = 0
      t = lane
      while t < rank
        px = sus[t]
        while px != 0
          px = px & (px - 1)
          localden = localden + 1
        px = svs[t]
        while px != 0
          px = px & (px - 1)
          localden = localden + 1
        px = sws[t]
        while px != 0
          px = px & (px - 1)
          localden = localden + 1
        t = t + 32
      dsum = simd_sum(localden)
      if lane == 0
        capture = 0
        if rank < best
          capture = 1
        if rank == best
          if dsum < bestden
            capture = 1
        if capture == 1
          best = rank
          bestden = dsum
          captures = captures + 1
      capture = simd_broadcast_first(capture)
      best = simd_broadcast_first(best)
      bestden = simd_broadcast_first(bestden)
      captures = simd_broadcast_first(captures)
      if capture == 1
        t = lane
        while t < rank
          best_us[base + t] = sus[t]
          best_vs[base + t] = svs[t]
          best_ws[base + t] = sws[t]
          t = t + 32
      threadgroup_barrier()
    step = step + 1

  i = lane
  while i < rank
    work_us[base + i] = sus[i]
    work_vs[base + i] = svs[i]
    work_ws[base + i] = sws[i]
    i = i + 32
  if lane == 0
    st[sb] = rank
    st[sb + 1] = best
    st[sb + 2] = state
    st[sb + 3] = bestden
    st[sb + 4] = attempts
    st[sb + 5] = partners
    st[sb + 6] = captures
    st[sb + 7] = 1

# ---------------- host ----------------
use core/metal

-> popcnt(v) (i64) i64
  c = 0
  x = v
  while x != 0
    x = x & (x - 1)
    c += 1
  c

# Exhaustive coefficient check, independent of the randomized Freivalds gate
# used by the long-running relay.  At 6x6 this checks all 46,656 tensor cells.
-> verify_full(us, vs, ws, rank, nn, mm, pp) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  ab = nn * mm
  bb = mm * pp
  cb = nn * pp
  if rank < 1
    return 0
  one = 1 ## i64
  amask = (one << ab) - 1 ## i64
  bmask = (one << bb) - 1 ## i64
  cmask = (one << cb) - 1 ## i64
  t = 0 ## i64
  while t < rank
    if us[t] == 0 || vs[t] == 0 || ws[t] == 0
      return 0
    if (us[t] & amask) != us[t]
      return 0
    if (vs[t] & bmask) != vs[t]
      return 0
    if (ws[t] & cmask) != ws[t]
      return 0
    # A duplicate pair cancels over GF(2), so accepting one would advertise a
    # rank that is two terms larger than the decomposition actually represents.
    j = t + 1 ## i64
    while j < rank
      if us[t] == us[j] && vs[t] == vs[j] && ws[t] == ws[j]
        return 0
      j += 1
    t += 1
  ok = 1
  ai = 0
  while ai < ab
    bi = 0
    while bi < bb
      ci = 0
      while ci < cb
        got = 0
        t = 0
        while t < rank
          if ((us[t] >> ai) & 1) == 1
            if ((vs[t] >> bi) & 1) == 1
              if ((ws[t] >> ci) & 1) == 1
                got = got ^ 1
          t += 1
        arow = ai / mm
        acol = ai % mm
        brow = bi / pp
        bcol = bi % pp
        crow = ci / pp
        ccol = ci % pp
        want = 0
        if acol == brow
          if arow == crow
            if bcol == ccol
              want = 1
        if got != want
          ok = 0
        ci += 1
      bi += 1
    ai += 1
  ok

CAP = 144
GROUPS = 1024
STEPS = 20000
DISPATCHES = 5
MARGIN = 4
MODE = 0
MASK_BYTES = 4
nn = 5
mm = 5
pp = 5

seedpath = "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt"
outpath = "/tmp/flipgraph_gpu_simdgroup_best_555.txt"
av = argv()
if av.size() > 0
  seedpath = av[0]
if av.size() > 1
  outpath = av[1]
if av.size() > 2
  GROUPS = av[2].to_i()
if av.size() > 3
  STEPS = av[3].to_i()
if av.size() > 4
  DISPATCHES = av[4].to_i()
if av.size() > 5
  MARGIN = av[5].to_i()
if av.size() > 6
  MODE = av[6].to_i()
metallibpath = ""
if av.size() > 7
  metallibpath = av[7]

content = read_file(seedpath)
lines = content.split("\n")
startrank = lines[0].to_i()
rowbase = 1
colbase = 0
firstparts = lines[0].split(" ")
if firstparts[0] == "R"
  # MP-style tracked schemes contain one `R u v w` term per line and no rank
  # header.  Bare FlipFleet dumps retain the historical header format.
  rowbase = 0
  colbase = 1
  startrank = lines.size()
  if lines[startrank - 1].size() == 0
    startrank -= 1
seedu = i64[CAP]
seedv = i64[CAP]
seedw = i64[CAP]
ii = 0
seedden = 0
while ii < startrank
  parts = lines[ii + rowbase].split(" ")
  seedu[ii] = parts[colbase].to_i()
  seedv[ii] = parts[colbase + 1].to_i()
  seedw[ii] = parts[colbase + 2].to_i()
  seedden = seedden + popcnt(seedu[ii]) + popcnt(seedv[ii]) + popcnt(seedw[ii])
  ii += 1

device = metal_device()
library = nil
if metallibpath != ""
  library = metal_load_library(device, metallibpath)
if library == nil
  msl = read_file("benchmarks/matmul/metaflip/simd_bundle/simdgroup_555.metal")
  library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "flipwalk_simd")
work_us = metal_buffer(device, GROUPS * CAP * MASK_BYTES)
work_vs = metal_buffer(device, GROUPS * CAP * MASK_BYTES)
work_ws = metal_buffer(device, GROUPS * CAP * MASK_BYTES)
best_us = metal_buffer(device, GROUPS * CAP * MASK_BYTES)
best_vs = metal_buffer(device, GROUPS * CAP * MASK_BYTES)
best_ws = metal_buffer(device, GROUPS * CAP * MASK_BYTES)
st = metal_buffer(device, GROUPS * 8 * 4)
seed_us = metal_buffer(device, CAP * MASK_BYTES)
seed_vs = metal_buffer(device, CAP * MASK_BYTES)
seed_ws = metal_buffer(device, CAP * MASK_BYTES)
params = metal_buffer(device, 7 * 4)

ii = 0
while ii < startrank
  metal_buffer_write_i32(seed_us, ii, seedu[ii])
  metal_buffer_write_i32(seed_vs, ii, seedv[ii])
  metal_buffer_write_i32(seed_ws, ii, seedw[ii])
  ii += 1
metal_buffer_write_i32(params, 0, startrank)
metal_buffer_write_i32(params, 1, CAP)
metal_buffer_write_i32(params, 2, STEPS)
metal_buffer_write_i32(params, 3, 1)
metal_buffer_write_i32(params, 4, MARGIN)
metal_buffer_write_i32(params, 5, seedden)
metal_buffer_write_i32(params, 6, MODE)

queue = metal_queue(device)
bufs = [work_us, work_vs, work_ws, best_us, best_vs, best_ws, st, seed_us, seed_vs, seed_ws, params]
d = 0
t0 = ccall("__w_clock_ms")
while d < DISPATCHES
  metal_dispatch_groups(queue, pipeline, bufs, GROUPS, 32)
  metal_buffer_write_i32(params, 3, 0)
  d += 1
t1 = ccall("__w_clock_ms")

bestgroup = 0
bestrank = startrank
bestdensity = seedden
attemptsum = 0
partnersum = 0
g = 0
while g < GROUPS
  gr = metal_buffer_read_i32(st, g * 8 + 1)
  gd = metal_buffer_read_i32(st, g * 8 + 3)
  attemptsum += metal_buffer_read_i32(st, g * 8 + 4)
  partnersum += metal_buffer_read_i32(st, g * 8 + 5)
  better = 0
  if gr < bestrank
    better = 1
  if gr == bestrank
    if gd < bestdensity
      better = 1
  if better == 1
    bestgroup = g
    bestrank = gr
    bestdensity = gd
  g += 1

outu = i64[CAP]
outv = i64[CAP]
outw = i64[CAP]
ii = 0
while ii < bestrank
  outu[ii] = metal_buffer_read_i32(best_us, bestgroup * CAP + ii)
  outv[ii] = metal_buffer_read_i32(best_vs, bestgroup * CAP + ii)
  outw[ii] = metal_buffer_read_i32(best_ws, bestgroup * CAP + ii)
  ii += 1
vok = verify_full(outu, outv, outw, bestrank, nn, mm, pp)
body = bestrank.to_s() + "\n"
ii = 0
while ii < bestrank
  body = body + outu[ii].to_s() + " " + outv[ii].to_s() + " " + outw[ii].to_s() + "\n"
  ii += 1
if vok == 1
  write_file(outpath, body)

elapsed = t1 - t0
rate = 0
if elapsed > 0
  rate = attemptsum * 1000 / elapsed
perwalker = 0
if GROUPS > 0
  if elapsed > 0
    perwalker = (attemptsum / GROUPS) * 1000 / elapsed
<< "SIMDGROUP_RESULT mode=" + MODE.to_s() + " n=" + nn.to_s() + " groups=" + GROUPS.to_s() + " steps=" + STEPS.to_s() + " dispatches=" + DISPATCHES.to_s() + " elapsed_ms=" + elapsed.to_s() + " attempted=" + attemptsum.to_s() + " partners=" + partnersum.to_s() + " aggregate_steps_s=" + rate.to_s() + " trajectory_steps_s=" + perwalker.to_s() + " rank=" + bestrank.to_s() + " density=" + bestdensity.to_s() + " verify_full=" + vok.to_s() + " output=" + outpath
