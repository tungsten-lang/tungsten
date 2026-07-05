# GPU-parallel annealing flip-graph for <4,4,4> matmul rank, over GF(2).
# Thousands of independent walkers (one per GPU thread), each seeded from
# Strassen^2 (49), each doing plus-moves (rank up, to escape local minima),
# flips (flat), and reductions (down). Per-thread state persists in device
# buffers across many dispatches (so the walk continues; the GPU watchdog caps
# any single dispatch). Host reads each thread's best rank, recovers + verifies
# the best scheme. Below 49 beats Strassen^2; below 47 beats AlphaTensor.

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
  nterms = params[0] ## i32
  cap = params[1] ## i32
  steps = params[2] ## i32
  doinit = params[3] ## i32
  margin = params[4] ## i32
  base = tid * cap ## i32
  sb = tid * 4 ## i32
  i = 0 ## i32
  if doinit == 1
    i = 0
    while i < nterms
      work_us[base + i] = seed_us[i]
      work_vs[base + i] = seed_vs[i]
      work_ws[base + i] = seed_ws[i]
      best_us[base + i] = seed_us[i]
      best_vs[base + i] = seed_vs[i]
      best_ws[base + i] = seed_ws[i]
      i = i + 1
    st[sb] = nterms
    st[sb + 1] = nterms
    st[sb + 2] = 0
    st[sb + 3] = tid * 9973 + 12345
  rank = st[sb] ## i32
  best = st[sb + 1] ## i32
  since = st[sb + 2] ## i32
  state = st[sb + 3] ## i32
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
          if u1 != work_us[base + pt]
            work_us[base + rank] = work_us[base + pt] ^ u1
            work_vs[base + rank] = work_vs[base + pt]
            work_ws[base + rank] = work_ws[base + pt]
            work_us[base + pt] = u1
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
              if work_us[base + cand] == work_us[base + fi]
                fj = cand
            if axis == 1
              if work_vs[base + cand] == work_vs[base + fi]
                fj = cand
            if axis == 2
              if work_ws[base + cand] == work_ws[base + fi]
                fj = cand
        scan = scan + 1
      if fj >= 0
        if axis == 0
          work_ws[base + fi] = work_ws[base + fi] ^ work_ws[base + fj]
          work_vs[base + fj] = work_vs[base + fi] ^ work_vs[base + fj]
        if axis == 1
          work_ws[base + fi] = work_ws[base + fi] ^ work_ws[base + fj]
          work_us[base + fj] = work_us[base + fi] ^ work_us[base + fj]
        if axis == 2
          work_vs[base + fi] = work_vs[base + fi] ^ work_vs[base + fj]
          work_us[base + fj] = work_us[base + fi] ^ work_us[base + fj]
    t = 0
    while t < rank
      z = 0
      if work_us[base + t] == 0
        z = 1
      if work_vs[base + t] == 0
        z = 1
      if work_ws[base + t] == 0
        z = 1
      if z == 1
        work_us[base + t] = work_us[base + rank - 1]
        work_vs[base + t] = work_vs[base + rank - 1]
        work_ws[base + t] = work_ws[base + rank - 1]
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
            if work_us[base + a] == work_us[base + bb]
              if work_vs[base + a] == work_vs[base + bb]
                if work_ws[base + a] == work_ws[base + bb]
                  dup = bb
          bb = bb + 1
        if dup >= 0
          work_us[base + dup] = work_us[base + rank - 1]
          work_vs[base + dup] = work_vs[base + rank - 1]
          work_ws[base + dup] = work_ws[base + rank - 1]
          rank = rank - 1
          work_us[base + a] = work_us[base + rank - 1]
          work_vs[base + a] = work_vs[base + rank - 1]
          work_ws[base + a] = work_ws[base + rank - 1]
          rank = rank - 1
        if dup < 0
          a = a + 1
    if rank < best
      best = rank
      ci = 0
      while ci < rank
        best_us[base + ci] = work_us[base + ci]
        best_vs[base + ci] = work_vs[base + ci]
        best_ws[base + ci] = work_ws[base + ci]
        ci = ci + 1
      since = 0
    if rank >= best
      since = since + 1
    if since > 250000
      ci = 0
      while ci < best
        work_us[base + ci] = best_us[base + ci]
        work_vs[base + ci] = best_vs[base + ci]
        work_ws[base + ci] = best_ws[base + ci]
        ci = ci + 1
      rank = best
      since = 0
    step = step + 1
  st[sb] = rank
  st[sb + 1] = best
  st[sb + 2] = since
  st[sb + 3] = state

# ---------------- host ----------------
use core/metal

-> parity(mask, vec, dim) (i64 i64 i64)
  p = 0
  b = 0
  while b < dim
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        p = (p + 1) % 2
    b += 1
  p

-> verify(us, vs, ws, rank, seed0) (i64[] i64[] i64[] i64 i64)
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

# Verify a scheme stored in metal buffers (read scalars directly -- never store
# a GPU read into an i64[] slot, which the compiler 0xFFFA-tags).
-> verify_buf(bufu, bufv, bufw, baseoff, rank, seed0)
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

# Build the 49-term Strassen^2 seed (host).
p2 = i64[16]
p2[0] = 1
kk = 1
while kk < 16
  p2[kk] = p2[kk - 1] + p2[kk - 1]
  kk += 1
su = i64[7]
sv = i64[7]
sw = i64[7]
su[0] = 9
su[1] = 12
su[2] = 1
su[3] = 8
su[4] = 3
su[5] = 5
su[6] = 10
sv[0] = 9
sv[1] = 1
sv[2] = 10
sv[3] = 5
sv[4] = 8
sv[5] = 3
sv[6] = 12
sw[0] = 9
sw[1] = 12
sw[2] = 10
sw[3] = 5
sw[4] = 3
sw[5] = 8
sw[6] = 1
seedu = i64[49]
seedv = i64[49]
seedw = i64[49]
nt = 0
ss = 0
while ss < 7
  tt = 0
  while tt < 7
    seedu[nt] = 0
    seedv[nt] = 0
    seedw[nt] = 0
    blk = 0
    while blk < 4
      scl = 0
      while scl < 4
        idx = (2 * (blk / 2) + scl / 2) * 4 + (2 * (blk % 2) + scl % 2)
        if ((su[ss] >> blk) & 1) == 1
          if ((su[tt] >> scl) & 1) == 1
            seedu[nt] = seedu[nt] ^ p2[idx]
        if ((sv[ss] >> blk) & 1) == 1
          if ((sv[tt] >> scl) & 1) == 1
            seedv[nt] = seedv[nt] ^ p2[idx]
        if ((sw[ss] >> blk) & 1) == 1
          if ((sw[tt] >> scl) & 1) == 1
            seedw[nt] = seedw[nt] ^ p2[idx]
        scl += 1
      blk += 1
    nt += 1
    tt += 1
  ss += 1
<< "seed Strassen^2 rank = " + nt.to_s() + "   verify = " + verify(seedu, seedv, seedw, nt, 999).to_s()

# GPU setup
msl = read_file("benchmarks/matmul/flipgraph_gpu.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "flipwalk")

NW = 2048
CAP = 96
STEPS = 120000
DISPATCHES = 60

work_us = metal_buffer(device, NW * CAP * 4)
work_vs = metal_buffer(device, NW * CAP * 4)
work_ws = metal_buffer(device, NW * CAP * 4)
best_us = metal_buffer(device, NW * CAP * 4)
best_vs = metal_buffer(device, NW * CAP * 4)
best_ws = metal_buffer(device, NW * CAP * 4)
st = metal_buffer(device, NW * 4 * 4)
seed_us = metal_buffer(device, 49 * 4)
seed_vs = metal_buffer(device, 49 * 4)
seed_ws = metal_buffer(device, 49 * 4)
params = metal_buffer(device, 5 * 4)

ii = 0
while ii < 49
  metal_buffer_write_i32(seed_us, ii, seedu[ii])
  metal_buffer_write_i32(seed_vs, ii, seedv[ii])
  metal_buffer_write_i32(seed_ws, ii, seedw[ii])
  ii += 1

metal_buffer_write_i32(params, 0, 49)
metal_buffer_write_i32(params, 1, CAP)
metal_buffer_write_i32(params, 2, STEPS)
metal_buffer_write_i32(params, 3, 1)
metal_buffer_write_i32(params, 4, 4)

queue = metal_queue(device)
bufs = [work_us, work_vs, work_ws, best_us, best_vs, best_ws, st, seed_us, seed_vs, seed_ws, params]

globalbest = 49
d = 0
while d < DISPATCHES
  metal_dispatch_n(queue, pipeline, bufs, NW)
  metal_buffer_write_i32(params, 3, 0)
  # scan best ranks
  w = 0
  localmin = 49
  bestthread = 0
  while w < NW
    bw = metal_buffer_read_i32(st, w * 4 + 1)
    if bw < localmin
      localmin = bw
      bestthread = w
    w += 1
  if localmin < globalbest
    globalbest = localmin
    << "dispatch " + d.to_s() + "  global best rank = " + globalbest.to_s() + "  (thread " + bestthread.to_s() + ")"
  write_file("/tmp/fgpu_progress.txt", "dispatch " + (d + 1).to_s() + "/" + DISPATCHES.to_s() + "  global_best=" + globalbest.to_s() + "  dispatch_min=" + localmin.to_s())
  d += 1

# recover + verify the global best scheme
w = 0
localmin = 49
bestthread = 0
while w < NW
  bw = metal_buffer_read_i32(st, w * 4 + 1)
  if bw < localmin
    localmin = bw
    bestthread = w
  w += 1
vok = verify_buf(best_us, best_vs, best_ws, bestthread * CAP, localmin, 555)
<< ""
<< "GPU DONE.  best rank over " + NW.to_s() + " walkers = " + localmin.to_s() + "   verify = " + vok.to_s() + "   (Strassen^2 49, AlphaTensor 47)"
