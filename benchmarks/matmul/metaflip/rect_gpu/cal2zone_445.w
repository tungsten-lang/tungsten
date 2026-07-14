# GPU relay running the ACTUAL cal2zone schedule per-thread (not the old
# margin/leash heuristic, and not best-of-N candidate scoring). Rationale for
# dropping best-of-N here: earlier debugging established that even a cheap
# O(rank) single-candidate walk needs ~2,000,000 steps to find its first
# lucky descent at rank~64 — best-of-N's O(rank^2) per-step cost cuts the
# achievable step count by ~64x for the same wall-clock budget, which starves
# the schedule of the raw step volume it needs to ever escalate through
# multiple bands. The GPU's actual edge over 18 CPU processes is parallel
# breadth (thousands of independent attempts), not smarter per-step choices,
# so this kernel goes back to cheap first-found selection and spends the
# saved budget on more total steps instead.
#
# Per-thread cal2zone state (mirrors bucket_gen.py's cal2zone mode exactly,
# just with move-quanta scaled down — GPU threads run ~1/1000th the speed of
# a CPU walker since throughput comes from thread COUNT, not per-thread
# speed, so CPU's 2B/500M-move quanta would take a single GPU thread days to
# traverse once):
#   aband  - current band, starts at 1 (bstart)
#   wthr   - work/wander zone boundary, starts at wthr0 (7), self-calibrates
#            UP-ONLY: any descent sets wthr = max(wthr, descent_band + 1)
#   wraps  - counts genuine hit-60-and-wrap cycles (NOT descent-triggered
#            resets); at 2, reset RNG + reset the whole scheme back to
#            whatever this dispatch's seed was (the doinit init, redone)
#   mv     - this thread's own cumulative move counter
#   nextesc - mv value at which to next check for band escalation
# Any descent (rank < best) resets aband back to bstart(=1) immediately.
#
# Re-seeding uses a portfolio of exact +1 split escapes derived from the CPU
# frontier.  Each GPU lane selects `tid % nseeds`, so the GPU spends its width
# in distinct basins instead of cloning the same seed thousands of times.
# Set ESCAPE_SEEDS=1 for the historical single-seed behavior.

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
  wqwork = params[5] ## i32
  wqwander = params[6] ## i32
  wthr0 = params[7] ## i32
  firstinit = params[8] ## i32
  nseeds = params[9] ## i32
  seedstride = params[10] ## i32
  base = tid * cap ## i32
  sb = tid * 9 ## i32
  seedid = tid % nseeds ## i32
  seedbase = seedid * seedstride ## i32
  sus = gpu.shared_i32(1792)
  svs = gpu.shared_i32(1792)
  sws = gpu.shared_i32(1792)
  i = 0 ## i32
  rank = 0 ## i32
  best = 0 ## i32
  state = 0 ## i32
  aband = 0 ## i32
  wthr = 0 ## i32
  wraps = 0 ## i32
  mv = 0 ## i32
  nextesc = 0 ## i32
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
  nb = 0 ## i32
  bestden = 0 ## i32
  dsum = 0 ## i32
  capit = 0 ## i32
  docap = 0 ## i32
  pz = 0 ## i32
  if doinit == 1
    i = 0
    while i < nterms
      sus[i * 16 + ltid] = seed_us[seedbase + i]
      svs[i * 16 + ltid] = seed_vs[seedbase + i]
      sws[i * 16 + ltid] = seed_ws[seedbase + i]
      best_us[base + i] = seed_us[seedbase + i]
      best_vs[base + i] = seed_vs[seedbase + i]
      best_ws[base + i] = seed_ws[seedbase + i]
      i = i + 1
    st[sb] = nterms
    st[sb + 1] = nterms
    st[sb + 2] = tid * 9973 + 12345
  if firstinit == 1
    st[sb + 3] = 1
    st[sb + 4] = wthr0
    st[sb + 5] = 0
    st[sb + 6] = 0
    st[sb + 7] = wqwork
    st[sb + 8] = 999999
  rank = st[sb]
  best = st[sb + 1]
  state = st[sb + 2]
  aband = st[sb + 3]
  wthr = st[sb + 4]
  wraps = st[sb + 5]
  mv = st[sb + 6]
  nextesc = st[sb + 7]
  bestden = st[sb + 8]
  if doinit == 0
    i = 0
    while i < rank
      sus[i * 16 + ltid] = work_us[base + i]
      svs[i * 16 + ltid] = work_vs[base + i]
      sws[i * 16 + ltid] = work_ws[base + i]
      i = i + 1
  step = 0
  while step < steps
    mv = mv + 1
    state = state * 1103515245 + 12345
    roll = ((state % 6) + 6) % 6
    didplus = 0
    if roll == 0
      if rank < best + margin
        if rank < cap - 1
          state = state * 1103515245 + 12345
          pt = ((state % rank) + rank) % rank
          state = state * 1103515245 + 12345
          # <4,4,5> factors span 16/20/20 bits.  Sample the 20-bit envelope, then trim it to the selected axis.
          u1 = (((state % 1048575) + 1048575) % 1048575) + 1
          state = state * 1103515245 + 12345
          paxis = ((state % 3) + 3) % 3
          if paxis == 0
            u1 = u1 & 65535
          if paxis == 1
            u1 = u1 & 1048575
          if paxis == 2
            u1 = u1 & 1048575
          if u1 == 0
            u1 = 1
          pb = pt * 16 + ltid
          if paxis == 0
            if u1 != sus[pb]
              sus[rank * 16 + ltid] = sus[pb] ^ u1
              svs[rank * 16 + ltid] = svs[pb]
              sws[rank * 16 + ltid] = sws[pb]
              sus[pb] = u1
              rank = rank + 1
              didplus = 1
          if paxis == 1
            if u1 != svs[pb]
              svs[rank * 16 + ltid] = svs[pb] ^ u1
              sus[rank * 16 + ltid] = sus[pb]
              sws[rank * 16 + ltid] = sws[pb]
              svs[pb] = u1
              rank = rank + 1
              didplus = 1
          if paxis == 2
            if u1 != sws[pb]
              sws[rank * 16 + ltid] = sws[pb] ^ u1
              sus[rank * 16 + ltid] = sus[pb]
              svs[rank * 16 + ltid] = svs[pb]
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
              if sus[cand * 16 + ltid] == sus[fi * 16 + ltid]
                fj = cand
            if axis == 1
              if svs[cand * 16 + ltid] == svs[fi * 16 + ltid]
                fj = cand
            if axis == 2
              if sws[cand * 16 + ltid] == sws[fi * 16 + ltid]
                fj = cand
        scan = scan + 1
      if fj >= 0
        if axis == 0
          sws[fi * 16 + ltid] = sws[fi * 16 + ltid] ^ sws[fj * 16 + ltid]
          svs[fj * 16 + ltid] = svs[fi * 16 + ltid] ^ svs[fj * 16 + ltid]
        if axis == 1
          sws[fi * 16 + ltid] = sws[fi * 16 + ltid] ^ sws[fj * 16 + ltid]
          sus[fj * 16 + ltid] = sus[fi * 16 + ltid] ^ sus[fj * 16 + ltid]
        if axis == 2
          svs[fi * 16 + ltid] = svs[fi * 16 + ltid] ^ svs[fj * 16 + ltid]
          sus[fj * 16 + ltid] = sus[fi * 16 + ltid] ^ sus[fj * 16 + ltid]
    t = 0
    while t < rank
      z = 0
      if sus[t * 16 + ltid] == 0
        z = 1
      if svs[t * 16 + ltid] == 0
        z = 1
      if sws[t * 16 + ltid] == 0
        z = 1
      if z == 1
        sus[t * 16 + ltid] = sus[(rank - 1) * 16 + ltid]
        svs[t * 16 + ltid] = svs[(rank - 1) * 16 + ltid]
        sws[t * 16 + ltid] = sws[(rank - 1) * 16 + ltid]
        rank = rank - 1
      if z == 0
        t = t + 1
    # O(rank) duplicate check: a duplicate can only newly appear at a slot
    # touched THIS step (the flip's fi/fj, or the plus-move's new slot at
    # rank-1) — every other term didn't change, so if it wasn't a duplicate
    # before it still isn't. Check just the touched slot(s) against the rest
    # every step, instead of an O(rank^2) all-pairs scan periodically.
    if didplus == 1
      a = rank - 1
      if a >= 0
        dup = -1
        bb = 0
        while bb < a
          if dup < 0
            if sus[a * 16 + ltid] == sus[bb * 16 + ltid]
              if svs[a * 16 + ltid] == svs[bb * 16 + ltid]
                if sws[a * 16 + ltid] == sws[bb * 16 + ltid]
                  dup = bb
          bb = bb + 1
        if dup >= 0
          sus[dup * 16 + ltid] = sus[(rank - 1) * 16 + ltid]
          svs[dup * 16 + ltid] = svs[(rank - 1) * 16 + ltid]
          sws[dup * 16 + ltid] = sws[(rank - 1) * 16 + ltid]
          rank = rank - 1
          sus[a * 16 + ltid] = sus[(rank - 1) * 16 + ltid]
          svs[a * 16 + ltid] = svs[(rank - 1) * 16 + ltid]
          sws[a * 16 + ltid] = sws[(rank - 1) * 16 + ltid]
          rank = rank - 1
    if didplus == 0
      a = fi
      if a < rank
        dup = -1
        bb = 0
        while bb < rank
          if dup < 0
            if bb != a
              if sus[a * 16 + ltid] == sus[bb * 16 + ltid]
                if svs[a * 16 + ltid] == svs[bb * 16 + ltid]
                  if sws[a * 16 + ltid] == sws[bb * 16 + ltid]
                    dup = bb
          bb = bb + 1
        if dup >= 0
          sus[dup * 16 + ltid] = sus[(rank - 1) * 16 + ltid]
          svs[dup * 16 + ltid] = svs[(rank - 1) * 16 + ltid]
          sws[dup * 16 + ltid] = sws[(rank - 1) * 16 + ltid]
          rank = rank - 1
          sus[a * 16 + ltid] = sus[(rank - 1) * 16 + ltid]
          svs[a * 16 + ltid] = svs[(rank - 1) * 16 + ltid]
          sws[a * 16 + ltid] = sws[(rank - 1) * 16 + ltid]
          rank = rank - 1
      a = fj
      if a < rank
        dup = -1
        bb = 0
        while bb < rank
          if dup < 0
            if bb != a
              if sus[a * 16 + ltid] == sus[bb * 16 + ltid]
                if svs[a * 16 + ltid] == svs[bb * 16 + ltid]
                  if sws[a * 16 + ltid] == sws[bb * 16 + ltid]
                    dup = bb
          bb = bb + 1
        if dup >= 0
          sus[dup * 16 + ltid] = sus[(rank - 1) * 16 + ltid]
          svs[dup * 16 + ltid] = svs[(rank - 1) * 16 + ltid]
          sws[dup * 16 + ltid] = sws[(rank - 1) * 16 + ltid]
          rank = rank - 1
          sus[a * 16 + ltid] = sus[(rank - 1) * 16 + ltid]
          svs[a * 16 + ltid] = svs[(rank - 1) * 16 + ltid]
          sws[a * 16 + ltid] = sws[(rank - 1) * 16 + ltid]
          rank = rank - 1
    dchk = step % 4096
    if dchk == 0
      a = 0
      while a < rank
        dup = -1
        bb = a + 1
        while bb < rank
          if dup < 0
            if sus[a * 16 + ltid] == sus[bb * 16 + ltid]
              if svs[a * 16 + ltid] == svs[bb * 16 + ltid]
                if sws[a * 16 + ltid] == sws[bb * 16 + ltid]
                  dup = bb
          bb = bb + 1
        if dup >= 0
          sus[dup * 16 + ltid] = sus[(rank - 1) * 16 + ltid]
          svs[dup * 16 + ltid] = svs[(rank - 1) * 16 + ltid]
          sws[dup * 16 + ltid] = sws[(rank - 1) * 16 + ltid]
          rank = rank - 1
          sus[a * 16 + ltid] = sus[(rank - 1) * 16 + ltid]
          svs[a * 16 + ltid] = svs[(rank - 1) * 16 + ltid]
          sws[a * 16 + ltid] = sws[(rank - 1) * 16 + ltid]
          rank = rank - 1
        if dup < 0
          a = a + 1
    # Capture best by lexicographic (rank, density): a strictly lower rank
    # always wins; at equal rank, lower total density (mask popcount = base-case
    # ops) wins. On a rank drop we must recompute density; while sitting AT the
    # best rank we sample density only every 64 steps (the O(rank*bits) popcount
    # would otherwise dominate the hot loop at the frontier).
    docap = 0
    if rank < best
      docap = 1
    if rank == best
      if (step % 64) == 0
        docap = 1
    if docap == 1
      dsum = 0
      ci = 0
      while ci < rank
        pz = sus[ci * 16 + ltid]
        while pz != 0
          pz = pz & (pz - 1)
          dsum = dsum + 1
        pz = svs[ci * 16 + ltid]
        while pz != 0
          pz = pz & (pz - 1)
          dsum = dsum + 1
        pz = sws[ci * 16 + ltid]
        while pz != 0
          pz = pz & (pz - 1)
          dsum = dsum + 1
        ci = ci + 1
      capit = 0
      if rank < best
        capit = 1
      if rank == best
        if dsum < bestden
          capit = 1
      if capit == 1
        best = rank
        bestden = dsum
        ci = 0
        while ci < rank
          best_us[base + ci] = sus[ci * 16 + ltid]
          best_vs[base + ci] = svs[ci * 16 + ltid]
          best_ws[base + ci] = sws[ci * 16 + ltid]
          ci = ci + 1
        if aband + 1 > wthr
          wthr = aband + 1
        aband = 1
    if mv >= nextesc
      nb = aband + 1
      if aband > wthr
        nb = aband + 12
      if nb > 60
        nb = 1
        wraps = wraps + 1
        if wraps >= 2
          wraps = 0
          state = ((state ^ (mv & 2147483647)) * 1103515245 + 54321) & 2147483647
          state = state * 1103515245 + 12345
          state = state * 1103515245 + 12345
          i = 0
          while i < nterms
            sus[i * 16 + ltid] = seed_us[seedbase + i]
            svs[i * 16 + ltid] = seed_vs[seedbase + i]
            sws[i * 16 + ltid] = seed_ws[seedbase + i]
            i = i + 1
          rank = nterms
          best = nterms
          bestden = 999999
          ci = 0
          while ci < nterms
            best_us[base + ci] = seed_us[seedbase + ci]
            best_vs[base + ci] = seed_vs[seedbase + ci]
            best_ws[base + ci] = seed_ws[seedbase + ci]
            ci = ci + 1
      aband = nb
      if aband > wthr
        nextesc = mv + wqwander
      if aband <= wthr
        nextesc = mv + wqwork
    step = step + 1
  i = 0
  while i < rank
    work_us[base + i] = sus[i * 16 + ltid]
    work_vs[base + i] = svs[i * 16 + ltid]
    work_ws[base + i] = sws[i * 16 + ltid]
    i = i + 1
  st[sb] = rank
  st[sb + 1] = best
  st[sb + 2] = state
  st[sb + 3] = aband
  st[sb + 4] = wthr
  st[sb + 5] = wraps
  st[sb + 6] = mv
  st[sb + 7] = nextesc
  st[sb + 8] = bestden

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

-> popcnt(v) (i64) i64
  c = 0
  x = v
  while x != 0
    x = x & (x - 1)
    c += 1
  c

-> verify_buf(bufu, bufv, bufw, baseoff, rank, seed0, nn, mm, pp) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  # This is an adoption gate, not a probabilistic corruption check.  Copy the
  # candidate out of Metal once, reject malformed factors, then reconstruct
  # every A[i,j] * B[j,k] -> C[i,k] tensor coordinate over GF(2).  The bundle
  # is specialized for <4,4,5>; its configured CAP is below 512.
  ab = nn * mm
  bb = mm * pp
  cb = nn * pp
  if rank < 1 || rank > 512
    return 0
  one = 1 ## i64
  amask = (one << ab) - 1 ## i64
  bmask = (one << bb) - 1 ## i64
  cmask = (one << cb) - 1 ## i64
  cus = i64[512]
  cvs = i64[512]
  cws = i64[512]
  t = 0 ## i64
  while t < rank
    cus[t] = metal_buffer_read_i32(bufu, baseoff + t)
    cvs[t] = metal_buffer_read_i32(bufv, baseoff + t)
    cws[t] = metal_buffer_read_i32(bufw, baseoff + t)
    if cus[t] == 0 || cvs[t] == 0 || cws[t] == 0
      return 0
    if (cus[t] & amask) != cus[t]
      return 0
    if (cvs[t] & bmask) != cvs[t]
      return 0
    if (cws[t] & cmask) != cws[t]
      return 0
    t += 1
  ai = 0 ## i64
  while ai < ab
    bi = 0 ## i64
    while bi < bb
      ci = 0 ## i64
      while ci < cb
        got = 0 ## i64
        t = 0
        while t < rank
          if ((cus[t] >> ai) & 1) == 1
            if ((cvs[t] >> bi) & 1) == 1
              if ((cws[t] >> ci) & 1) == 1
                got = got ^ 1
          t += 1
        want = 0 ## i64
        if (ai / mm) == (ci / pp)
          if (ai % mm) == (bi / pp)
            if (bi % pp) == (ci % pp)
              want = 1
        if got != want
          return 0
        ci += 1
      bi += 1
    ai += 1
  1

-> gpu_mailbox_ack(path, body) (String String) i64
  tmp = path + ".tmp"
  wrote = write_file(tmp, body)
  if wrote
    moved = ccall("__w_rename", tmp, path)
    if moved
      return 1
  0

NW = 4096
WPG = 16
CAP = 112
STEPS = 500000
# Re-seed (reset each thread back to the seed + band-1 fresh start) only every
# RESEED_EVERY rounds instead of every round, so a thread runs STEPS*RESEED_EVERY
# = 500000*200 = 100,000,000 moves of continuous descent before it resets. Kept
# as many small STEPS-sized dispatches (not one giant dispatch) to stay well
# under Metal's GPU-command watchdog. Between re-seeds threads continue from their
# saved working scheme + band state (doinit=0 path).
RESEED_EVERY = 200
ROUNDS = 1000000
MARGIN = 4
WQWORK = 150000
WQWANDER = 60000
WTHR0 = 7
ESCAPE_SEEDS = 256

seedpath = "benchmarks/matmul/metaflip/runs/run_445/current_best.txt"
gpubestpath = "benchmarks/matmul/metaflip/runs/run_445/gpu_best.txt"
nn = 4
mm = 4
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
recordpath = ""
recordtarget = 0
if av0.size() > 6
  recordpath = av0[5]
  recordtarget = av0[6].to_i()
recordhit = 0

# ---- optional hyperparameters (av0[7..13]) for flipfleet --gpu-only sweeps ----
if av0.size() > 7
  STEPS = av0[7].to_i()
if av0.size() > 8
  RESEED_EVERY = av0[8].to_i()
if av0.size() > 9
  MARGIN = av0[9].to_i()
if av0.size() > 10
  WQWORK = av0[10].to_i()
if av0.size() > 11
  WQWANDER = av0[11].to_i()
if av0.size() > 12
  WTHR0 = av0[12].to_i()
if av0.size() > 13
  NW = av0[13].to_i()
# av0[14] = a live-params file we poll each round (for restart-free sweeps).
# Line 0 = "STEPS RESEED MARGIN WORKQ WANDERQ WTHR GEN"; a new GEN forces a reseed.
livepath = ""
if av0.size() > 14
  livepath = av0[14]
# av0[15] = exact split-escape portfolio size.  One restores the historical
# behavior.  Values above NW are pointless because no lane can select them.
if av0.size() > 15
  ESCAPE_SEEDS = av0[15].to_i()
if ESCAPE_SEEDS < 1
  ESCAPE_SEEDS = 1
if ESCAPE_SEEDS > NW
  ESCAPE_SEEDS = NW
# av0[16] bounds one native scheduler epoch.  The historical default remains
# effectively unbounded; FlipFleet passes a small value and reallocates roles
# between epochs from their measured candidate yield.
if av0.size() > 16
  ROUNDS = av0[16].to_i()
if ROUNDS < 1
  ROUNDS = 1
# av0[17] is an optional offline-compiled library.  Native FlipFleet always
# supplies it; the source path remains available for standalone/dev launches.
metallibpath = ""
if av0.size() > 17
  metallibpath = av0[17]
persistent_command_path = ""
persistent_ack_path = ""
if av0.size() > 19
  persistent_command_path = av0[18]
  persistent_ack_path = av0[19]
persistent_mode = 0
if persistent_command_path != "" && persistent_ack_path != ""
  persistent_mode = 1
persistent_escape_cap = ESCAPE_SEEDS ## i64
live_gen = 0
<< "GPU cfg: NW=" + NW.to_s() + " STEPS=" + STEPS.to_s() + " ROUNDS=" + ROUNDS.to_s() + " RESEED=" + RESEED_EVERY.to_s() + " MARGIN=" + MARGIN.to_s() + " WORKQ=" + WQWORK.to_s() + " WANDERQ=" + WQWANDER.to_s() + " WTHR=" + WTHR0.to_s() + " ESCAPES=" + ESCAPE_SEEDS.to_s()
flush()

seedu = i64[112 * ESCAPE_SEEDS]
seedv = i64[112 * ESCAPE_SEEDS]
seedw = i64[112 * ESCAPE_SEEDS]
baseu = i64[112]
basev = i64[112]
basew = i64[112]

device = metal_device()
library = nil
if metallibpath != ""
  library = metal_load_library(device, metallibpath)
if library == nil
  msl = read_file("benchmarks/matmul/metaflip/rect_gpu/cal2zone_445.metal")
  library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "flipwalk")

work_us = metal_buffer(device, NW * CAP * 4)
work_vs = metal_buffer(device, NW * CAP * 4)
work_ws = metal_buffer(device, NW * CAP * 4)
best_us = metal_buffer(device, NW * CAP * 4)
best_vs = metal_buffer(device, NW * CAP * 4)
best_ws = metal_buffer(device, NW * CAP * 4)
st = metal_buffer(device, NW * 9 * 4)
seed_us = metal_buffer(device, 112 * ESCAPE_SEEDS * 4)
seed_vs = metal_buffer(device, 112 * ESCAPE_SEEDS * 4)
seed_ws = metal_buffer(device, 112 * ESCAPE_SEEDS * 4)
params = metal_buffer(device, 11 * 4)
queue = metal_queue(device)
bufs = [work_us, work_vs, work_ws, best_us, best_vs, best_ws, st, seed_us, seed_vs, seed_ws, params]

globalbest = 999
rd = 0
last_baserank = -1
last_seedden = -1
persistent_generation = 0 ## i64
if persistent_mode == 1
  z = gpu_mailbox_ack(persistent_ack_path, "0 ready 0\n")
while rd < ROUNDS || persistent_mode == 1
  command_force_reseed = 0 ## i64
  if persistent_mode == 1
    command_ready = 0 ## i64
    while command_ready == 0
      command_text = read_file(persistent_command_path)
      if command_text != nil
        command_lines = command_text.split("\n")
        if command_lines.size() > 0
          command_parts = command_lines[0].split(" ")
          if command_parts.size() >= 9
            command_generation = command_parts[0].to_i() ## i64
            if command_generation > persistent_generation
              command_action = command_parts[1].to_i() ## i64
              persistent_generation = command_generation
              if command_action == 0
                z = gpu_mailbox_ack(persistent_ack_path, persistent_generation.to_s() + " stopped " + rd.to_s() + "\n")
                exit(0)
              STEPS = command_parts[2].to_i()
              RESEED_EVERY = command_parts[3].to_i()
              MARGIN = command_parts[4].to_i()
              WQWORK = command_parts[5].to_i()
              WQWANDER = command_parts[6].to_i()
              WTHR0 = command_parts[7].to_i()
              ESCAPE_SEEDS = command_parts[8].to_i()
              if STEPS < 1
                STEPS = 1
              if RESEED_EVERY < 1
                RESEED_EVERY = 1
              if ESCAPE_SEEDS < 1
                ESCAPE_SEEDS = 1
              if ESCAPE_SEEDS > persistent_escape_cap
                ESCAPE_SEEDS = persistent_escape_cap
              command_force_reseed = 1
              # Retire the previous command's candidate atomically.  Reuse the
              # mailbox writer so readers never observe a partially truncated
              # result file while the persistent process stays alive.
              z = gpu_mailbox_ack(gpubestpath, "")
              command_ready = 1
      if command_ready == 0
        z = ccall("__w_sleep_ms", 10)
  content = read_file(seedpath)
  lines = content.split("\n")
  baserank = lines[0].to_i()
  ti2 = 0
  while ti2 < baserank
    ln = lines[ti2 + 1]
    parts = ln.split(" ")
    baseu[ti2] = parts[0].to_i()
    basev[ti2] = parts[1].to_i()
    basew[ti2] = parts[2].to_i()
    ti2 += 1
  # Build exact split identities natively.  Portfolio slot 0 is the base seed
  # when ESCAPE_SEEDS=1.  Otherwise every slot replaces one term by two terms
  # whose selected factors XOR back to the original, so tensor value is exact.
  startrank = baserank
  if ESCAPE_SEEDS > 1
    startrank = baserank + 1
  sid = 0
  while sid < ESCAPE_SEEDS
    soff = sid * 112
    ii = 0
    while ii < baserank
      seedu[soff + ii] = baseu[ii]
      seedv[soff + ii] = basev[ii]
      seedw[soff + ii] = basew[ii]
      ii += 1
    if ESCAPE_SEEDS > 1
      axis = sid % 3
      escape_index = sid / 3
      target = (escape_index * 37 + axis * 13 + rd * 17) % baserank
      donor = (target + 1 + sid * 13) % baserank
      oldfactor = baseu[target]
      part = baseu[donor]
      if axis == 1
        oldfactor = basev[target]
        part = basev[donor]
      if axis == 2
        oldfactor = basew[target]
        part = basew[donor]
      tries = 0
      while (part == 0 || part == oldfactor) && tries < baserank
        donor = (donor + 1) % baserank
        part = baseu[donor]
        if axis == 1
          part = basev[donor]
        if axis == 2
          part = basew[donor]
        tries += 1
      # Every practical frontier has at least two factors on each live axis;
      # retain a deterministic algebraic fallback for malformed portfolios.
      if part == 0 || part == oldfactor
        part = oldfactor ^ 1
        if part == 0
          part = 2
      seedu[soff + baserank] = baseu[target]
      seedv[soff + baserank] = basev[target]
      seedw[soff + baserank] = basew[target]
      if axis == 0
        seedu[soff + target] = part
        seedu[soff + baserank] = oldfactor ^ part
      if axis == 1
        seedv[soff + target] = part
        seedv[soff + baserank] = oldfactor ^ part
      if axis == 2
        seedw[soff + target] = part
        seedw[soff + baserank] = oldfactor ^ part
    ii = 0
    while ii < startrank
      metal_buffer_write_i32(seed_us, soff + ii, seedu[soff + ii])
      metal_buffer_write_i32(seed_vs, soff + ii, seedv[soff + ii])
      metal_buffer_write_i32(seed_ws, soff + ii, seedw[soff + ii])
      ii += 1
    sid += 1
  # density (total mask popcount = base-case ops budget) of the current seed;
  # a same-rank GPU candidate only counts as an improvement if it beats this.
  force_reseed = 0
  if command_force_reseed == 1
    force_reseed = 1
  seedden = 0
  ii = 0
  while ii < baserank
    seedden = seedden + popcnt(baseu[ii]) + popcnt(basev[ii]) + popcnt(basew[ii])
    ii += 1
  if baserank != last_baserank || seedden != last_seedden
    force_reseed = 1
    last_baserank = baserank
    last_seedden = seedden
  # poll the live-params file (restart-free sweep); a new GEN forces a reseed
  if livepath != ""
    livec = read_file(livepath)
    if livec != nil
      livel = livec.split("\n")
      if livel.size() > 0
        lparts = livel[0].split(" ")
        if lparts.size() > 6
          STEPS = lparts[0].to_i()
          RESEED_EVERY = lparts[1].to_i()
          MARGIN = lparts[2].to_i()
          WQWORK = lparts[3].to_i()
          WQWANDER = lparts[4].to_i()
          WTHR0 = lparts[5].to_i()
          if RESEED_EVERY < 1
            RESEED_EVERY = 1
          newgen = lparts[6].to_i()
          if newgen != live_gen
            force_reseed = 1
            live_gen = newgen
            << "LIVE gen=" + newgen.to_s() + " STEPS=" + STEPS.to_s() + " RESEED=" + RESEED_EVERY.to_s() + " MARGIN=" + MARGIN.to_s() + " WORKQ=" + WQWORK.to_s() + " WANDERQ=" + WQWANDER.to_s() + " WTHR=" + WTHR0.to_s()
            flush()
  metal_buffer_write_i32(params, 0, startrank)
  metal_buffer_write_i32(params, 1, CAP)
  metal_buffer_write_i32(params, 2, STEPS)
  reseed = 0
  if (rd % RESEED_EVERY) == 0
    reseed = 1
  if force_reseed == 1
    reseed = 1
  metal_buffer_write_i32(params, 3, reseed)
  metal_buffer_write_i32(params, 4, MARGIN)
  metal_buffer_write_i32(params, 5, WQWORK)
  metal_buffer_write_i32(params, 6, WQWANDER)
  metal_buffer_write_i32(params, 7, WTHR0)
  metal_buffer_write_i32(params, 8, reseed)
  metal_buffer_write_i32(params, 9, ESCAPE_SEEDS)
  metal_buffer_write_i32(params, 10, 112)
  metal_dispatch_groups(queue, pipeline, bufs, NW / WPG, WPG)
  # pick the lexicographic (rank, density) best thread: lower rank wins; at equal
  # rank, lower density (fewer base-case ops) wins.
  w = 0
  localmin = startrank
  localden = 999999999
  bestthread = 0
  while w < NW
    bw = metal_buffer_read_i32(st, w * 9 + 1)
    bd = metal_buffer_read_i32(st, w * 9 + 8)
    better = 0
    if bw < localmin
      better = 1
    if bw == localmin
      if bd < localden
        better = 1
    if better == 1
      localmin = bw
      localden = bd
      bestthread = w
    w += 1
  # improvement = lower rank than the seed, OR same rank at strictly lower density
  improved = 0
  if localmin < baserank
    improved = 1
  if localmin == baserank
    if localden < seedden
      improved = 1
  if improved == 1
    vok = verify_buf(best_us, best_vs, best_ws, bestthread * CAP, localmin, 555, nn, mm, pp)
    if vok == 1
      body = localmin.to_s() + " " + localden.to_s() + "\n"
      di = 0
      while di < localmin
        uu = metal_buffer_read_i32(best_us, bestthread * CAP + di)
        vv = metal_buffer_read_i32(best_vs, bestthread * CAP + di)
        ww = metal_buffer_read_i32(best_ws, bestthread * CAP + di)
        body = body + uu.to_s() + " " + vv.to_s() + " " + ww.to_s() + "\n"
        di += 1
      write_file(gpubestpath, body)
      << "round " + rd.to_s() + "  GPU IMPROVED  rank " + baserank.to_s() + " (launch " + startrank.to_s() + ") -> " + localmin.to_s() + "  density " + seedden.to_s() + " -> " + localden.to_s() + "  verify=" + vok.to_s()
      flush()
      if localmin < globalbest
        globalbest = localmin
      if recordpath.size() > 0
        if localmin <= recordtarget
          recordhit = recordhit + 1
          write_file(recordpath + "_" + recordhit.to_s() + ".txt", body)
  << "round " + rd.to_s() + "/" + ROUNDS.to_s() + "  base=" + baserank.to_s() + "  launch=" + startrank.to_s() + "  escapes=" + ESCAPE_SEEDS.to_s() + "  seed_density=" + seedden.to_s() + "  round_best=" + localmin.to_s() + "  round_density=" + localden.to_s() + "  global_best=" + globalbest.to_s()
  flush()
  rd += 1
  if persistent_mode == 1
    ack_body = persistent_generation.to_s() + " done " + rd.to_s() + " " + localmin.to_s() + " " + localden.to_s() + "\n"
    z = gpu_mailbox_ack(persistent_ack_path, ack_body)

<< ""
<< "GPU-CAL2ZONE DONE.  global best over " + ROUNDS.to_s() + " rounds x " + NW.to_s() + " walkers = " + globalbest.to_s()
