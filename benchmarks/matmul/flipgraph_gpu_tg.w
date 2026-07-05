# GPU flip-graph for <4,4,4>, THREADGROUP-MEMORY variant. Each walker's working
# scheme lives in on-chip threadgroup memory (fast, no register spill), with a
# coalesced per-thread layout sus[term*32 + ltid] (adjacent walkers -> adjacent
# addresses, no bank conflicts). 32 walkers per threadgroup; CAP=56 so 3*56*32 =
# 5376 ints = 21KB < 32KB threadgroup limit. best/persistence stay in device mem.

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
  base = tid * cap ## i32
  sb = tid * 4 ## i32
  sus = gpu.shared_i32(2304)
  svs = gpu.shared_i32(2304)
  sws = gpu.shared_i32(2304)
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
  off = 0 ## i32
  fj = 0 ## i32
  scan = 0 ## i32
  cand = 0 ## i32
  t = 0 ## i32
  z = 0 ## i32
  a = 0 ## i32
  bb = 0 ## i32
  dup = 0 ## i32
  ci = 0 ## i32
  dchk = 0 ## i32
  pb = 0 ## i32
  paxis = 0 ## i32
  if doinit == 1
    i = 0
    while i < nterms
      sus[i * 32 + ltid] = seed_us[i]
      svs[i * 32 + ltid] = seed_vs[i]
      sws[i * 32 + ltid] = seed_ws[i]
      best_us[base + i] = seed_us[i]
      best_vs[base + i] = seed_vs[i]
      best_ws[base + i] = seed_ws[i]
      i = i + 1
    st[sb] = nterms
    st[sb + 1] = nterms
    st[sb + 2] = 0
    st[sb + 3] = tid * 9973 + 12345
  rank = st[sb]
  best = st[sb + 1]
  since = st[sb + 2]
  state = st[sb + 3]
  if doinit == 0
    i = 0
    while i < rank
      sus[i * 32 + ltid] = work_us[base + i]
      svs[i * 32 + ltid] = work_vs[base + i]
      sws[i * 32 + ltid] = work_ws[base + i]
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
          pb = pt * 32 + ltid
          if paxis == 0
            if u1 != sus[pb]
              sus[rank * 32 + ltid] = sus[pb] ^ u1
              svs[rank * 32 + ltid] = svs[pb]
              sws[rank * 32 + ltid] = sws[pb]
              sus[pb] = u1
              rank = rank + 1
              didplus = 1
          if paxis == 1
            if u1 != svs[pb]
              svs[rank * 32 + ltid] = svs[pb] ^ u1
              sus[rank * 32 + ltid] = sus[pb]
              sws[rank * 32 + ltid] = sws[pb]
              svs[pb] = u1
              rank = rank + 1
              didplus = 1
          if paxis == 2
            if u1 != sws[pb]
              sws[rank * 32 + ltid] = sws[pb] ^ u1
              sus[rank * 32 + ltid] = sus[pb]
              svs[rank * 32 + ltid] = svs[pb]
              sws[pb] = u1
              rank = rank + 1
              didplus = 1
    if didplus == 0
      state = state * 1103515245 + 12345
      fi = ((state % rank) + rank) % rank
      state = state * 1103515245 + 12345
      axis = ((state % 3) + 3) % 3
      state = state * 1103515245 + 12345
      off = ((state % rank) + rank) % rank
      fj = -1
      scan = 0
      while scan < rank
        if fj < 0
          cand = (off + scan) % rank
          if cand != fi
            if axis == 0
              if sus[cand * 32 + ltid] == sus[fi * 32 + ltid]
                fj = cand
            if axis == 1
              if svs[cand * 32 + ltid] == svs[fi * 32 + ltid]
                fj = cand
            if axis == 2
              if sws[cand * 32 + ltid] == sws[fi * 32 + ltid]
                fj = cand
        scan = scan + 1
      if fj >= 0
        if axis == 0
          sws[fi * 32 + ltid] = sws[fi * 32 + ltid] ^ sws[fj * 32 + ltid]
          svs[fj * 32 + ltid] = svs[fi * 32 + ltid] ^ svs[fj * 32 + ltid]
        if axis == 1
          sws[fi * 32 + ltid] = sws[fi * 32 + ltid] ^ sws[fj * 32 + ltid]
          sus[fj * 32 + ltid] = sus[fi * 32 + ltid] ^ sus[fj * 32 + ltid]
        if axis == 2
          svs[fi * 32 + ltid] = svs[fi * 32 + ltid] ^ svs[fj * 32 + ltid]
          sus[fj * 32 + ltid] = sus[fi * 32 + ltid] ^ sus[fj * 32 + ltid]
    t = 0
    while t < rank
      z = 0
      if sus[t * 32 + ltid] == 0
        z = 1
      if svs[t * 32 + ltid] == 0
        z = 1
      if sws[t * 32 + ltid] == 0
        z = 1
      if z == 1
        sus[t * 32 + ltid] = sus[(rank - 1) * 32 + ltid]
        svs[t * 32 + ltid] = svs[(rank - 1) * 32 + ltid]
        sws[t * 32 + ltid] = sws[(rank - 1) * 32 + ltid]
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
            if sus[a * 32 + ltid] == sus[bb * 32 + ltid]
              if svs[a * 32 + ltid] == svs[bb * 32 + ltid]
                if sws[a * 32 + ltid] == sws[bb * 32 + ltid]
                  dup = bb
          bb = bb + 1
        if dup >= 0
          sus[dup * 32 + ltid] = sus[(rank - 1) * 32 + ltid]
          svs[dup * 32 + ltid] = svs[(rank - 1) * 32 + ltid]
          sws[dup * 32 + ltid] = sws[(rank - 1) * 32 + ltid]
          rank = rank - 1
          sus[a * 32 + ltid] = sus[(rank - 1) * 32 + ltid]
          svs[a * 32 + ltid] = svs[(rank - 1) * 32 + ltid]
          sws[a * 32 + ltid] = sws[(rank - 1) * 32 + ltid]
          rank = rank - 1
        if dup < 0
          a = a + 1
    if rank < best
      best = rank
      ci = 0
      while ci < rank
        best_us[base + ci] = sus[ci * 32 + ltid]
        best_vs[base + ci] = svs[ci * 32 + ltid]
        best_ws[base + ci] = sws[ci * 32 + ltid]
        ci = ci + 1
      since = 0
    if rank >= best
      since = since + 1
    if since > 250000
      ci = 0
      while ci < best
        sus[ci * 32 + ltid] = best_us[base + ci]
        svs[ci * 32 + ltid] = best_vs[base + ci]
        sws[ci * 32 + ltid] = best_ws[base + ci]
        ci = ci + 1
      rank = best
      since = 0
    step = step + 1
  i = 0
  while i < rank
    work_us[base + i] = sus[i * 32 + ltid]
    work_vs[base + i] = svs[i * 32 + ltid]
    work_ws[base + i] = sws[i * 32 + ltid]
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

-> verify(us, vs, ws, rank, seed0) (i64[] i64[] i64[] i64 i64) i64
  ok = 1
  s = seed0
  trial = 0
  while trial < 40
    s = (s * 1103515245 + 12345) % 2147483648
    av = s % 65536
    s = (s * 1103515245 + 12345) % 2147483648
    bv = s % 65536
    o = 0
    while o < 16
      cs = 0
      t = 0
      while t < rank
        if ((ws[t] >> o) & 1) == 1
          la = parity(us[t], av, 16)
          lb = parity(vs[t], bv, 16)
          if la == 1
            if lb == 1
              cs = (cs + 1) % 2
        t += 1
      oi = o / 4
      oj = o % 4
      ct = 0
      k = 0
      while k < 4
        if ((av >> (oi * 4 + k)) & 1) == 1
          if ((bv >> (k * 4 + oj)) & 1) == 1
            ct = (ct + 1) % 2
        k += 1
      if cs != ct
        ok = 0
      o += 1
    trial += 1
  ok

-> verify_buf(bufu, bufv, bufw, baseoff, rank, seed0) (i64[] i64[] i64[] i64 i64 i64) i64
  ok = 1
  s = seed0
  trial = 0
  while trial < 40
    s = (s * 1103515245 + 12345) % 2147483648
    av = s % 65536
    s = (s * 1103515245 + 12345) % 2147483648
    bv = s % 65536
    o = 0
    while o < 16
      cs = 0
      t = 0
      while t < rank
        wt = metal_buffer_read_i32(bufw, baseoff + t)
        if ((wt >> o) & 1) == 1
          ut = metal_buffer_read_i32(bufu, baseoff + t)
          vt = metal_buffer_read_i32(bufv, baseoff + t)
          la = parity(ut, av, 16)
          lb = parity(vt, bv, 16)
          if la == 1
            if lb == 1
              cs = (cs + 1) % 2
        t += 1
      oi = o / 4
      oj = o % 4
      ct = 0
      k = 0
      while k < 4
        if ((av >> (oi * 4 + k)) & 1) == 1
          if ((bv >> (k * 4 + oj)) & 1) == 1
            ct = (ct + 1) % 2
        k += 1
      if cs != ct
        ok = 0
      o += 1
    trial += 1
  ok

p2 = i64[16]
p2[0] = 1
kk = 1
while kk < 16
  p2[kk] = p2[kk - 1] + p2[kk - 1]
  kk += 1
seedu = i64[64]
seedv = i64[64]
seedw = i64[64]
nt = 0
ni = 0
while ni < 4
  nj = 0
  while nj < 4
    nk = 0
    while nk < 4
      seedu[nt] = p2[ni * 4 + nj]
      seedv[nt] = p2[nj * 4 + nk]
      seedw[nt] = p2[ni * 4 + nk]
      nt += 1
      nk += 1
    nj += 1
  ni += 1
<< "seed naive-64 rank = " + nt.to_s() + "   verify = " + verify(seedu, seedv, seedw, nt, 999).to_s()

msl = read_file("benchmarks/matmul/flipgraph_gpu_tg.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "flipwalk")

NW = 4096
CAP = 72
STEPS = 120000
DISPATCHES = 30

work_us = metal_buffer(device, NW * CAP * 4)
work_vs = metal_buffer(device, NW * CAP * 4)
work_ws = metal_buffer(device, NW * CAP * 4)
best_us = metal_buffer(device, NW * CAP * 4)
best_vs = metal_buffer(device, NW * CAP * 4)
best_ws = metal_buffer(device, NW * CAP * 4)
st = metal_buffer(device, NW * 4 * 4)
seed_us = metal_buffer(device, 64 * 4)
seed_vs = metal_buffer(device, 64 * 4)
seed_ws = metal_buffer(device, 64 * 4)
params = metal_buffer(device, 5 * 4)

ii = 0
while ii < 64
  metal_buffer_write_i32(seed_us, ii, seedu[ii])
  metal_buffer_write_i32(seed_vs, ii, seedv[ii])
  metal_buffer_write_i32(seed_ws, ii, seedw[ii])
  ii += 1
metal_buffer_write_i32(params, 0, 64)
metal_buffer_write_i32(params, 1, CAP)
metal_buffer_write_i32(params, 2, STEPS)
metal_buffer_write_i32(params, 3, 1)
metal_buffer_write_i32(params, 4, 4)

queue = metal_queue(device)
bufs = [work_us, work_vs, work_ws, best_us, best_vs, best_ws, st, seed_us, seed_vs, seed_ws, params]

globalbest = 64
d = 0
tstart = ccall("__w_clock_ms")
while d < DISPATCHES
  metal_dispatch_groups(queue, pipeline, bufs, NW / 32, 32)
  metal_buffer_write_i32(params, 3, 0)
  w = 0
  localmin = 64
  bestthread = 0
  while w < NW
    bw = metal_buffer_read_i32(st, w * 4 + 1)
    if bw < localmin
      localmin = bw
      bestthread = w
    w += 1
  if localmin < globalbest
    globalbest = localmin
    << "dispatch " + d.to_s() + "  global best rank = " + globalbest.to_s()
  write_file("~/.mmwork/fgpu_tg_progress.txt", "dispatch " + (d + 1).to_s() + "/" + DISPATCHES.to_s() + "  global_best=" + globalbest.to_s())
  d += 1
tend = ccall("__w_clock_ms")

w = 0
localmin = 64
bestthread = 0
while w < NW
  bw = metal_buffer_read_i32(st, w * 4 + 1)
  if bw < localmin
    localmin = bw
    bestthread = w
  w += 1
vok = verify_buf(best_us, best_vs, best_ws, bestthread * CAP, localmin, 555)
totalmoves = NW * STEPS * DISPATCHES
elapsed_ms = tend - tstart
<< ""
<< "GPU-TG DONE.  best rank over " + NW.to_s() + " walkers = " + localmin.to_s() + "   verify = " + vok.to_s() + "   (naive 64, AlphaTensor 47)"
<< "elapsed_ms=" + elapsed_ms.to_s() + "  total_moves=" + totalmoves.to_s()
