# GPU RELAY, BEST-OF-N + SHORT LEASH variant. Same file-based relay design as
# flipgraph_gpu_relay.w (re-seed from a shared "current best" file each round,
# run a short burst, write back any improvement) but the per-thread move
# logic is now genuine best-of-N candidate selection, not first-found:
#
#   - flipgraph_gpu_tg.w's per-step logic scanned candidates from a random
#     offset and committed the FIRST valid match — that's still a single-
#     candidate random walk, just implemented via linear scan instead of a
#     CPU-style hash chain. It is NOT the algorithm Phase 0 validated.
#   - THIS kernel scans ALL `rank` candidates for the chosen reference term +
#     axis, scores each by a local pressure heuristic (count of other terms
#     in THIS walker's own scheme sharing exactly 2 of the 3 (u,v,w) factors
#     with the candidate's hypothetical flip output — the same "share-2-of-3"
#     semantics as bucket_gen.py's hash-chain-based pressure(), just computed
#     via linear scan since a GPU thread's local array has no hash chain),
#     and commits the single best-scoring one. This mirrors the CPU
#     "bestof" selection rule Phase 0 validated, executed independently by
#     thousands of GPU threads in parallel instead of one CPU thread.
#   - "short leash": the reset-to-personal-best threshold (`since`) is a few
#     hundred steps, not 250,000 — each walker gets snapped back to its own
#     best quickly if it drifts, matching the restart-swarm-beats-marathon
#     finding from earlier sessions, now applied WITHIN each short round.
#
# Cost: best-of-N scoring is O(rank) candidates x O(rank) pressure lookup
# each = O(rank^2) per step, vs. O(rank) for first-found. Shared memory is
# correspondingly tighter: 16 walkers/threadgroup (not 32) so CAP=140 (rank
# up to ~125 + plus-move margin) still fits the 32KB threadgroup budget.

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
@gpu fn flipwalk(work_us, work_vs, work_ws, best_us, best_vs, best_ws, st, seed_us, seed_vs, seed_ws, params)
  tid = gpu.thread_position_in_grid.x ## i32
  ltid = gpu.thread_position_in_threadgroup.x ## i32
  nterms = params[0] ## i32
  cap = params[1] ## i32
  steps = params[2] ## i32
  doinit = params[3] ## i32
  margin = params[4] ## i32
  leash = params[5] ## i32
  gatethr = params[6] ## i32
  base = tid * cap ## i32
  sb = tid * 4 ## i32
  sus = gpu.shared_i32(2000)
  svs = gpu.shared_i32(2000)
  sws = gpu.shared_i32(2000)
  i = 0 ## i32
  rank = 0 ## i32
  best = 0 ## i32
  since = 0 ## i32
  state = 0 ## i32
  step = 0 ## i32
  roll = 0 ## i32
  didplus = 0 ## i32
  pt = 0 ## i32
  u1 = 0 ## i32
  fi = 0 ## i32
  axis = 0 ## i32
  fiu = 0 ## i32
  fiv = 0 ## i32
  fiw = 0 ## i32
  bestscore = 0 ## i32
  bestfj = 0 ## i32
  scan = 0 ## i32
  matched = 0 ## i32
  cuj = 0 ## i32
  cvj = 0 ## i32
  cwj = 0 ## i32
  cau = 0 ## i32
  cav = 0 ## i32
  caw = 0 ## i32
  cbu = 0 ## i32
  cbv = 0 ## i32
  cbw = 0 ## i32
  pa = 0 ## i32
  pb = 0 ## i32
  z3 = 0 ## i32
  mu = 0 ## i32
  mv3 = 0 ## i32
  mw3 = 0 ## i32
  score = 0 ## i32
  wj = 0 ## i32
  wuj = 0 ## i32
  wvj = 0 ## i32
  wwj = 0 ## i32
  wau = 0 ## i32
  wav = 0 ## i32
  waw = 0 ## i32
  wbu = 0 ## i32
  wbv = 0 ## i32
  wbw = 0 ## i32
  t = 0 ## i32
  z = 0 ## i32
  a = 0 ## i32
  bb = 0 ## i32
  dup = 0 ## i32
  ci = 0 ## i32
  dchk = 0 ## i32
  pb2 = 0 ## i32
  paxis = 0 ## i32
  polda = 0 ## i32
  poldb = 0 ## i32
  pold = 0 ## i32
  pnew = 0 ## i32
  acc = 0 ## i32
  if doinit == 1
    i = 0
    while i < nterms
      sus[i * 8 + ltid] = seed_us[i]
      svs[i * 8 + ltid] = seed_vs[i]
      sws[i * 8 + ltid] = seed_ws[i]
      best_us[base + i] = seed_us[i]
      best_vs[base + i] = seed_vs[i]
      best_ws[base + i] = seed_ws[i]
      i = i + 1
    st[sb] = nterms
    st[sb + 1] = nterms
    st[sb + 2] = 0
    st[sb + 3] = tid * 9973 + 12345 + step
  rank = st[sb]
  best = st[sb + 1]
  since = st[sb + 2]
  state = st[sb + 3]
  if doinit == 0
    i = 0
    while i < rank
      sus[i * 8 + ltid] = work_us[base + i]
      svs[i * 8 + ltid] = work_vs[base + i]
      sws[i * 8 + ltid] = work_ws[base + i]
      i = i + 1
  step = 0
  while step < steps
    state = state * 1103515245 + 12345
    roll = ((state % 6) + 6) % 6
    didplus = 0
    if roll == 0
      if rank < best + margin
        if rank < cap - 1
          state = state * 1103515245 + 12345
          pt = ((state % rank) + rank) % rank
          state = state * 1103515245 + 12345
          u1 = (((state % 65535) + 65535) % 65535) + 1
          state = state * 1103515245 + 12345
          paxis = ((state % 3) + 3) % 3
          pb2 = pt * 8 + ltid
          if paxis == 0
            if u1 != sus[pb2]
              sus[rank * 8 + ltid] = sus[pb2] ^ u1
              svs[rank * 8 + ltid] = svs[pb2]
              sws[rank * 8 + ltid] = sws[pb2]
              sus[pb2] = u1
              rank = rank + 1
              didplus = 1
          if paxis == 1
            if u1 != svs[pb2]
              svs[rank * 8 + ltid] = svs[pb2] ^ u1
              sus[rank * 8 + ltid] = sus[pb2]
              sws[rank * 8 + ltid] = sws[pb2]
              svs[pb2] = u1
              rank = rank + 1
              didplus = 1
          if paxis == 2
            if u1 != sws[pb2]
              sws[rank * 8 + ltid] = sws[pb2] ^ u1
              sus[rank * 8 + ltid] = sus[pb2]
              svs[rank * 8 + ltid] = svs[pb2]
              sws[pb2] = u1
              rank = rank + 1
              didplus = 1
    if didplus == 0
      state = state * 1103515245 + 12345
      fi = ((state % rank) + rank) % rank
      state = state * 1103515245 + 12345
      axis = ((state % 3) + 3) % 3
      fiu = sus[fi * 8 + ltid]
      fiv = svs[fi * 8 + ltid]
      fiw = sws[fi * 8 + ltid]
      bestscore = 0 - 1000000000
      bestfj = -1
      scan = 0
      while scan < rank
        if scan != fi
          matched = 0
          if axis == 0
            if sus[scan * 8 + ltid] == fiu
              matched = 1
          if axis == 1
            if svs[scan * 8 + ltid] == fiv
              matched = 1
          if axis == 2
            if sws[scan * 8 + ltid] == fiw
              matched = 1
          if matched == 1
            cuj = sus[scan * 8 + ltid]
            cvj = svs[scan * 8 + ltid]
            cwj = sws[scan * 8 + ltid]
            cau = fiu
            cav = fiv
            caw = fiw
            cbu = fiu
            cbv = fiv
            cbw = cwj
            if axis == 0
              caw = fiw ^ cwj
              cbv = fiv ^ cvj
            if axis == 1
              caw = fiw ^ cwj
              cbu = fiu ^ cuj
            if axis == 2
              cav = fiv ^ cvj
              caw = fiw
              cbu = fiu ^ cuj
              cbv = cvj
              cbw = fiw
            pa = 0
            z3 = 0
            while z3 < rank
              if z3 != fi
                if z3 != scan
                  mu = 0
                  if sus[z3 * 8 + ltid] == cau
                    mu = 1
                  mv3 = 0
                  if svs[z3 * 8 + ltid] == cav
                    mv3 = 1
                  mw3 = 0
                  if sws[z3 * 8 + ltid] == caw
                    mw3 = 1
                  if mu + mv3 + mw3 == 2
                    pa = pa + 1
              z3 = z3 + 1
            pb = 0
            z3 = 0
            while z3 < rank
              if z3 != fi
                if z3 != scan
                  mu = 0
                  if sus[z3 * 8 + ltid] == cbu
                    mu = 1
                  mv3 = 0
                  if svs[z3 * 8 + ltid] == cbv
                    mv3 = 1
                  mw3 = 0
                  if sws[z3 * 8 + ltid] == cbw
                    mw3 = 1
                  if mu + mv3 + mw3 == 2
                    pb = pb + 1
              z3 = z3 + 1
            score = pa + pb
            if score > bestscore
              bestscore = score
              bestfj = scan
        scan = scan + 1
      if bestfj >= 0
        wj = bestfj
        wuj = sus[wj * 8 + ltid]
        wvj = svs[wj * 8 + ltid]
        wwj = sws[wj * 8 + ltid]
        polda = 0
        z3 = 0
        while z3 < rank
          if z3 != fi
            if z3 != wj
              mu = 0
              if sus[z3 * 8 + ltid] == fiu
                mu = 1
              mv3 = 0
              if svs[z3 * 8 + ltid] == fiv
                mv3 = 1
              mw3 = 0
              if sws[z3 * 8 + ltid] == fiw
                mw3 = 1
              if mu + mv3 + mw3 == 2
                polda = polda + 1
          z3 = z3 + 1
        poldb = 0
        z3 = 0
        while z3 < rank
          if z3 != fi
            if z3 != wj
              mu = 0
              if sus[z3 * 8 + ltid] == wuj
                mu = 1
              mv3 = 0
              if svs[z3 * 8 + ltid] == wvj
                mv3 = 1
              mw3 = 0
              if sws[z3 * 8 + ltid] == wwj
                mw3 = 1
              if mu + mv3 + mw3 == 2
                poldb = poldb + 1
          z3 = z3 + 1
        pold = polda + poldb
        pnew = bestscore
        acc = 0
        if pnew + gatethr >= pold
          acc = 1
        if acc == 1
          wau = fiu
          wav = fiv
          waw = fiw
          wbu = fiu
          wbv = fiv
          wbw = wwj
          if axis == 0
            waw = fiw ^ wwj
            wbv = fiv ^ wvj
          if axis == 1
            waw = fiw ^ wwj
            wbu = fiu ^ wuj
          if axis == 2
            wav = fiv ^ wvj
            waw = fiw
            wbu = fiu ^ wuj
            wbv = wvj
            wbw = fiw
          sus[fi * 8 + ltid] = wau
          svs[fi * 8 + ltid] = wav
          sws[fi * 8 + ltid] = waw
          sus[wj * 8 + ltid] = wbu
          svs[wj * 8 + ltid] = wbv
          sws[wj * 8 + ltid] = wbw
    t = 0
    while t < rank
      z = 0
      if sus[t * 8 + ltid] == 0
        z = 1
      if svs[t * 8 + ltid] == 0
        z = 1
      if sws[t * 8 + ltid] == 0
        z = 1
      if z == 1
        sus[t * 8 + ltid] = sus[(rank - 1) * 8 + ltid]
        svs[t * 8 + ltid] = svs[(rank - 1) * 8 + ltid]
        sws[t * 8 + ltid] = sws[(rank - 1) * 8 + ltid]
        rank = rank - 1
      if z == 0
        t = t + 1
    dchk = step % 8
    if dchk == 0
      a = 0
      while a < rank
        dup = -1
        bb = a + 1
        while bb < rank
          if dup < 0
            if sus[a * 8 + ltid] == sus[bb * 8 + ltid]
              if svs[a * 8 + ltid] == svs[bb * 8 + ltid]
                if sws[a * 8 + ltid] == sws[bb * 8 + ltid]
                  dup = bb
          bb = bb + 1
        if dup >= 0
          sus[dup * 8 + ltid] = sus[(rank - 1) * 8 + ltid]
          svs[dup * 8 + ltid] = svs[(rank - 1) * 8 + ltid]
          sws[dup * 8 + ltid] = sws[(rank - 1) * 8 + ltid]
          rank = rank - 1
          sus[a * 8 + ltid] = sus[(rank - 1) * 8 + ltid]
          svs[a * 8 + ltid] = svs[(rank - 1) * 8 + ltid]
          sws[a * 8 + ltid] = sws[(rank - 1) * 8 + ltid]
          rank = rank - 1
        if dup < 0
          a = a + 1
    if rank < best
      best = rank
      ci = 0
      while ci < rank
        best_us[base + ci] = sus[ci * 8 + ltid]
        best_vs[base + ci] = svs[ci * 8 + ltid]
        best_ws[base + ci] = sws[ci * 8 + ltid]
        ci = ci + 1
      since = 0
    if rank >= best
      since = since + 1
    if since > leash
      ci = 0
      while ci < best
        sus[ci * 8 + ltid] = best_us[base + ci]
        svs[ci * 8 + ltid] = best_vs[base + ci]
        sws[ci * 8 + ltid] = best_ws[base + ci]
        ci = ci + 1
      rank = best
      since = 0
    step = step + 1
  i = 0
  while i < rank
    work_us[base + i] = sus[i * 8 + ltid]
    work_vs[base + i] = svs[i * 8 + ltid]
    work_ws[base + i] = sws[i * 8 + ltid]
    i = i + 1
  st[sb] = rank
  st[sb + 1] = best
  st[sb + 2] = since
  st[sb + 3] = state

# ---------------- host ----------------
use core/metal

-> parity(mask, vec, dim) (i64 i64 i64) i64
  p = 0
  b = 0
  while b < dim
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        p = (p + 1) % 2
    b += 1
  p

-> verify_buf(bufu, bufv, bufw, baseoff, rank, seed0, nn, mm, pp) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  ab = nn * mm
  bb = mm * pp
  cb = nn * pp
  moda = 1
  z5 = 0
  while z5 < ab
    moda = moda * 2
    z5 += 1
  modb = 1
  z6 = 0
  while z6 < bb
    modb = modb * 2
    z6 += 1
  ok = 1
  s = seed0
  trial = 0
  while trial < 40
    s = (s * 1103515245 + 12345) % 2147483648
    av = s % moda
    s = (s * 1103515245 + 12345) % 2147483648
    bv = s % modb
    o = 0
    while o < cb
      cs = 0
      t = 0
      while t < rank
        wt = metal_buffer_read_i32(bufw, baseoff + t)
        if ((wt >> o) & 1) == 1
          ut = metal_buffer_read_i32(bufu, baseoff + t)
          vt = metal_buffer_read_i32(bufv, baseoff + t)
          la = parity(ut, av, ab)
          lb = parity(vt, bv, bb)
          if la == 1
            if lb == 1
              cs = (cs + 1) % 2
        t += 1
      oi = o / pp
      oj = o % pp
      ct = 0
      k = 0
      while k < mm
        if ((av >> (oi * mm + k)) & 1) == 1
          if ((bv >> (k * pp + oj)) & 1) == 1
            ct = (ct + 1) % 2
        k += 1
      if cs != ct
        ok = 0
      o += 1
    trial += 1
  ok

NW = 4096
WPG = 8
CAP = 250
SHORTSTEPS = 200000
ROUNDS = 1000000
LEASH = 5000
GATETHR = 2

seedpath = "/Users/erik/.mmwork/relay/current_best_555.txt"
gpubestpath = "/Users/erik/.mmwork/relay/gpu_best_555.txt"
nn = 5
mm = 5
pp = 5
av0 = argv()
if av0.size() > 0
  seedpath = av0[0]
if av0.size() > 1
  gpubestpath = av0[1]
if av0.size() > 4
  nn = av0[2].to_i()
  mm = av0[3].to_i()
  pp = av0[4].to_i()

seedu = i64[260]
seedv = i64[260]
seedw = i64[260]

msl = read_file("benchmarks/matmul/flipgraph_gpu_relay_bestof.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "flipwalk")

work_us = metal_buffer(device, NW * CAP * 4)
work_vs = metal_buffer(device, NW * CAP * 4)
work_ws = metal_buffer(device, NW * CAP * 4)
best_us = metal_buffer(device, NW * CAP * 4)
best_vs = metal_buffer(device, NW * CAP * 4)
best_ws = metal_buffer(device, NW * CAP * 4)
st = metal_buffer(device, NW * 4 * 4)
seed_us = metal_buffer(device, 260 * 4)
seed_vs = metal_buffer(device, 260 * 4)
seed_ws = metal_buffer(device, 260 * 4)
params = metal_buffer(device, 7 * 4)
queue = metal_queue(device)
bufs = [work_us, work_vs, work_ws, best_us, best_vs, best_ws, st, seed_us, seed_vs, seed_ws, params]

globalbest = 999
rd = 0
while rd < ROUNDS
  content = read_file(seedpath)
  lines = content.split("\n")
  startrank = lines[0].to_i()
  ti2 = 0
  while ti2 < startrank
    ln = lines[ti2 + 1]
    parts = ln.split(" ")
    seedu[ti2] = parts[0].to_i()
    seedv[ti2] = parts[1].to_i()
    seedw[ti2] = parts[2].to_i()
    ti2 += 1
  ii = 0
  while ii < startrank
    metal_buffer_write_i32(seed_us, ii, seedu[ii])
    metal_buffer_write_i32(seed_vs, ii, seedv[ii])
    metal_buffer_write_i32(seed_ws, ii, seedw[ii])
    ii += 1
  metal_buffer_write_i32(params, 0, startrank)
  metal_buffer_write_i32(params, 1, CAP)
  metal_buffer_write_i32(params, 2, SHORTSTEPS)
  metal_buffer_write_i32(params, 3, 1)
  metal_buffer_write_i32(params, 4, 4)
  metal_buffer_write_i32(params, 5, LEASH)
  metal_buffer_write_i32(params, 6, GATETHR)
  metal_dispatch_groups(queue, pipeline, bufs, NW / WPG, WPG)
  w = 0
  localmin = startrank
  bestthread = 0
  while w < NW
    bw = metal_buffer_read_i32(st, w * 4 + 1)
    if bw < localmin
      localmin = bw
      bestthread = w
    w += 1
  if localmin < startrank
    vok = verify_buf(best_us, best_vs, best_ws, bestthread * CAP, localmin, 555, nn, mm, pp)
    if vok == 1
      body = localmin.to_s() + "\n"
      di = 0
      while di < localmin
        uu = metal_buffer_read_i32(best_us, bestthread * CAP + di)
        vv = metal_buffer_read_i32(best_vs, bestthread * CAP + di)
        ww = metal_buffer_read_i32(best_ws, bestthread * CAP + di)
        body = body + uu.to_s() + " " + vv.to_s() + " " + ww.to_s() + "\n"
        di += 1
      write_file(gpubestpath, body)
      << "round " + rd.to_s() + "  GPU IMPROVED " + startrank.to_s() + " -> " + localmin.to_s() + "  verify=" + vok.to_s()
      flush()
  if localmin < globalbest
    globalbest = localmin
  if (rd % 10) == 0
    << "round " + rd.to_s() + "/" + ROUNDS.to_s() + "  started_from=" + startrank.to_s() + "  round_best=" + localmin.to_s() + "  global_best=" + globalbest.to_s()
    flush()
  rd += 1

<< ""
<< "GPU-RELAY-BESTOF DONE.  global best over " + ROUNDS.to_s() + " rounds x " + NW.to_s() + " walkers = " + globalbest.to_s()
