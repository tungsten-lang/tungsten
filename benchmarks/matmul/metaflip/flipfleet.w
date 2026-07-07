# flipfleet.w — a threaded, in-process flip-graph matmul search with a live TUI,
# written entirely in Tungsten (no Python, no walker subprocesses).
#
# Each walker is one OS thread (Thread.new) running walk_worker() — the full
# hash-chain cal2zone2 walker (flipfleet_walker.w, generated from bucket_gen) —
# over its OWN i64[] state. A round spawns J threads, joins them, then the main
# thread does all coordination + I/O:
#   EXPLOIT — on a new fleet best, reseed every other walker onto it.
#   EXPLORE — a walker that CYCLEOUTs (sawtooth exhausted) is reseeded naive.
# DENSITY heuristic (-d): a lateral/uphill flip is only accepted if it does not
# raise total density by more than `dslack` bits — so descending rank ALSO cuts
# ops = bits - rank - outputs (base-case GF(2) work), not just the exponent.
#
# Build + run:  bin/tungsten -o flipfleet flipfleet.w && ./flipfleet -J 12 -d 4

use flipfleet_walker

RECORD = 93 ## i64
OUTPUTS = 25 ## i64          # n*p for <5,5,5>
NAIVE_OPS = 225 ## i64       # naive base-case op count, for reference
HK = 80 ## i64               # sparkline history length

# ---- argv:  -J <threads>   --steps <moves/round>   -d/--density <slack bits> ----
J = 8 ## i64
STEPS = 3000000 ## i64
DSLACK = 4 ## i64            # allowed density increase for a lateral flip (99 ~ off)
CYCLES = 4 ## i64            # sawtooth cycles before a walker CYCLEOUTs -> naive-wrap
GPU = 0 ## i64               # --gpu: run the Metal relay as a candidate scout
GPU_ONLY = 0 ## i64          # --gpu-only: no CPU walkers, just run+monitor the relay (for sweeps)
# GPU relay hyperparameters (defaults mirror flipgraph_gpu_cal2zone.w) — tunable for sweeps
GSTEPS = 500000 ## i64       # --gpu-steps    : moves per dispatch per thread
GRESEED = 200 ## i64         # --gpu-reseed   : dispatches between thread re-seeds
GMARGIN = 4 ## i64           # --gpu-margin   : leash above best before a flip is rejected
GWORKQ = 150000 ## i64       # --gpu-workq    : work-zone budget
GWANDERQ = 60000 ## i64      # --gpu-wanderq  : wander-zone budget
GWTHR = 7 ## i64             # --gpu-wthr     : work-zone band threshold
GNW = 4096 ## i64            # --gpu-nw       : GPU thread count (multiple of 16)
av = argv()
ai = 0 ## i64
while ai < av.size()
  a = av[ai]
  if a == "-J"
    if ai + 1 < av.size()
      J = av[ai + 1].to_i()
  if a == "--steps"
    if ai + 1 < av.size()
      STEPS = av[ai + 1].to_i()
  if a == "-d"
    if ai + 1 < av.size()
      DSLACK = av[ai + 1].to_i()
  if a == "--density"
    if ai + 1 < av.size()
      DSLACK = av[ai + 1].to_i()
  if a == "--cycles"
    if ai + 1 < av.size()
      CYCLES = av[ai + 1].to_i()
  if a == "--gpu"
    GPU = 1
  if a == "--gpu-only"
    GPU = 1
    GPU_ONLY = 1
  if a == "--gpu-steps"
    if ai + 1 < av.size()
      GSTEPS = av[ai + 1].to_i()
  if a == "--gpu-reseed"
    if ai + 1 < av.size()
      GRESEED = av[ai + 1].to_i()
  if a == "--gpu-margin"
    if ai + 1 < av.size()
      GMARGIN = av[ai + 1].to_i()
  if a == "--gpu-workq"
    if ai + 1 < av.size()
      GWORKQ = av[ai + 1].to_i()
  if a == "--gpu-wanderq"
    if ai + 1 < av.size()
      GWANDERQ = av[ai + 1].to_i()
  if a == "--gpu-wthr"
    if ai + 1 < av.size()
      GWTHR = av[ai + 1].to_i()
  if a == "--gpu-nw"
    if ai + 1 < av.size()
      GNW = av[ai + 1].to_i()
  ai += 1
if J < 1
  J = 1

# ---- sparkline of an i64 series (last `width`); lower value -> shorter bar ----
-> spark(arr, n, lo, hi, width) (i64[] i64 i64 i64 i64)
  blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
  span = hi - lo ## i64
  if span < 1
    span = 1
  s0 = 0 ## i64
  if n > width
    s0 = n - width
  out = ""
  i = s0 ## i64
  while i < n
    idx = ((arr[i] - lo) * 7) / span ## i64
    if idx < 0
      idx = 0
    if idx > 7
      idx = 7
    out = out + blocks[idx]
    i += 1
  out

# ---- allocate one state array per walker, seeded from naive ----
TOT = worker_st_size ## i64
sts = []
w = 0 ## i64
while w < J
  st = i64[TOT]
  z = init_naive(st, w * 97 + 13, DSLACK, CYCLES)
  sts.push(st)
  w += 1

rankhist = i64[80]
opshist = i64[80]
histn = 0 ## i64
fleet_best = 999 ## i64
best_ops = 0 ## i64
best_bitsv = 0 ## i64
best_valid = 1 ## i64
newbests = 0 ## i64
reseeds = 0 ## i64
naive_wraps = 0 ## i64
start = clock          # monotonic seconds since boot, a double — no ## i64
round = 0 ## i64

<< "flipfleet: " + J.to_s() + " threads, " + STEPS.to_s() + " mv/round, density-slack " + DSLACK.to_s() + ", cycles " + CYCLES.to_s() + ", <5,5,5> record=" + RECORD.to_s()
flush()

# ---- GPU candidate scout (opt-in --gpu): spawn the Metal relay detached. It
# reads GSEED (we keep it at the fleet frontier) and writes GBEST whenever a GPU
# thread beats the seed; we pull those into the worst CPU walker to dive. The
# seed/best/log live in the CWD (absolute paths); the relay itself is launched
# with its CWD walked up to the repo root (it hardcodes its .metal path there),
# so --gpu works from ANY directory inside the repo. ----
GSEED = "ff_gpu_seed.txt"
GBEST = "ff_gpu_best.txt"
gpu_seen = 999 ## i64
gpu_pulled = 999 ## i64
gpu_pulls = 0 ## i64
if GPU == 1
  zp = system("pwd > .ff_cwd.tmp 2>/dev/null")
  cwdc = read_file(".ff_cwd.tmp")
  cwd = "."
  if cwdc != nil
    cwd = cwdc.split("\n")[0]
  GSEED = cwd + "/ff_gpu_seed.txt"
  GBEST = cwd + "/ff_gpu_best.txt"
  glog = cwd + "/ff_gpu_log.txt"
  ds = dump_scheme(sts[0], GSEED)
  zc = write_file(GBEST, "")
  # walk up from the CWD to the repo root (where the relay's .metal lives)
  root = cwd
  found = 0 ## i64
  probes = 0 ## i64
  while probes < 8
    mp = read_file(root + "/benchmarks/matmul/flipgraph_gpu_cal2zone.metal")
    if mp != nil
      found = 1
      probes = 8
    if found == 0
      root = root + "/.."
    probes += 1
  hp = " x 0 " + GSTEPS.to_s() + " " + GRESEED.to_s() + " " + GMARGIN.to_s() + " " + GWORKQ.to_s() + " " + GWANDERQ.to_s() + " " + GWTHR.to_s() + " " + GNW.to_s()
  gcmd = "cd " + root + " && ./benchmarks/matmul/gpu_relay " + GSEED + " " + GBEST + " 5 5 5" + hp + " > " + glog + " 2>&1 &"
  zs = system(gcmd)
  << "  GPU relay spawned as candidate scout (log: " + glog + "). first descent ~15-30s (Metal compile). stop with: pkill gpu_relay"
  flush()

# ---- --gpu-only: no CPU walkers; just poll the relay + report (hyperparam sweeps) ----
if GPU_ONLY == 1
  << "  GPU-ONLY mode: no CPU walkers. reads flipfleet_status.txt for the sweep result. Ctrl-C then pkill gpu_relay to stop."
  flush()
  while round < 2000000000
    gc = read_file(GBEST)
    grank = 0 ## i64
    if gc != nil
      gl = gc.split("\n")
      if gl.size() > 0
        grank = gl[0].to_i()
    gpu_seen = grank
    el = (clock - start).to_i() ## i64
    if grank > 0
      if histn < HK
        rankhist[histn] = grank
        histn += 1
      else
        j = 0 ## i64
        while j < HK - 1
          rankhist[j] = rankhist[j + 1]
          j += 1
        rankhist[HK - 1] = grank
    << "\e[H\e[2J"
    << "\e[1;35m  flipfleet --gpu-only\e[0m  ⟨5,5,5⟩ GF(2)   \e[2melapsed\e[0m " + el.to_s() + "s"
    << ""
    << "  \e[2mGPU cfg\e[0m   nw " + GNW.to_s() + "   steps " + GSTEPS.to_s() + "   reseed " + GRESEED.to_s() + "   margin " + GMARGIN.to_s() + "   workq " + GWORKQ.to_s() + "   wanderq " + GWANDERQ.to_s() + "   wthr " + GWTHR.to_s()
    << ""
    if gpu_seen == 0
      << "  \e[2mGPU warming up (Metal compile + first dispatch, ~15-30s)...\e[0m"
    else
      gg = gpu_seen - RECORD ## i64
      << "  \e[1;32mGPU best  rank " + gpu_seen.to_s() + "\e[0m   \e[2m(+" + gg.to_s() + " to record " + RECORD.to_s() + ")\e[0m"
      if histn > 1
        << "  \e[35m" + spark(rankhist, histn, RECORD, 125, 60) + "\e[0m  \e[2m125→" + gpu_seen.to_s() + "\e[0m"
    << ""
    << "  \e[2msweep hook: flipfleet_status.txt updated each tick.  Ctrl-C to stop, then pkill gpu_relay.\e[0m"
    flush()
    sb = "gpu_only=1 gpu_best=" + gpu_seen.to_s() + " elapsed=" + el.to_s() + " nw=" + GNW.to_s() + " steps=" + GSTEPS.to_s() + " reseed=" + GRESEED.to_s() + " margin=" + GMARGIN.to_s() + " workq=" + GWORKQ.to_s() + " wanderq=" + GWANDERQ.to_s() + " wthr=" + GWTHR.to_s() + "\n"
    zw = write_file("flipfleet_status.txt", sb)
    zzz = system("sleep 2")
    round += 1

while round < 2000000000
  # ---- parallel round: J threads, each walks its own state, then join ----
  threads = []
  w = 0
  while w < J
    sw = sts[w]
    t = Thread.new ->
      bw = walk_worker(sw, STEPS)
    threads.push(t)
    w += 1
  w = 0
  while w < J
    threads[w].join
    w += 1

  # ---- fleet best over the round ----
  best = 999 ## i64
  bestw = 0 ## i64
  w = 0
  while w < J
    r = read_best_rank(sts[w]) ## i64
    if r < best
      best = r
      bestw = w
    w += 1

  # ---- EXPLOIT: new fleet best -> benchmark + reseed the others onto it ----
  if best < fleet_best
    fleet_best = best
    newbests += 1
    best_bitsv = best_bits(sts[bestw])
    best_ops = best_bitsv - best - OUTPUTS
    best_valid = verify_best(sts[bestw])
    src = sts[bestw]
    w = 0
    while w < J
      if w != bestw
        z = reseed_from(sts[w], src, round * 131 + w + 7)
        reseeds += 1
      w += 1

  # ---- EXPLORE: any walker at its sawtooth CYCLEOUT -> fresh naive ----
  w = 0
  while w < J
    if read_cycled(sts[w]) == 1
      z = init_naive(sts[w], round * 977 + w * 13 + 1, DSLACK, CYCLES)
      naive_wraps += 1
    w += 1

  # ---- GPU scout: keep its seed at the frontier, pull any improvement it finds ----
  if GPU == 1
    if fleet_best < 999
      if (round % 8) == 0
        gd = dump_scheme(sts[bestw], GSEED)
    gc = read_file(GBEST)
    grank = 0 ## i64
    if gc != nil
      gl = gc.split("\n")
      if gl.size() > 0
        grank = gl[0].to_i()
    gpu_seen = grank
    if grank > 0
      if grank < gpu_pulled
        if grank < fleet_best
          worstw = 0 ## i64
          worstr = 0 ## i64
          w = 0
          while w < J
            rr = read_best_rank(sts[w]) ## i64
            if rr > worstr
              worstr = rr
              worstw = w
            w += 1
          lr = load_scheme(sts[worstw], GBEST, round * 271 + 3)
          if verify_best(sts[worstw]) == 1
            gpu_pulls += 1
            gpu_pulled = grank

  # ---- record history for the sparklines ----
  if fleet_best < 999
    if histn < HK
      rankhist[histn] = fleet_best
      opshist[histn] = best_ops
      histn += 1
    else
      j = 0 ## i64
      while j < HK - 1
        rankhist[j] = rankhist[j + 1]
        opshist[j] = opshist[j + 1]
        j += 1
      rankhist[HK - 1] = fleet_best
      opshist[HK - 1] = best_ops

  gap = fleet_best - RECORD ## i64
  moves = round * J * STEPS ## i64
  el = (clock - start).to_i() ## i64

  # ---- TUI: redraw in place ----
  << "\e[H\e[2J"
  << "\e[1;33m  flipfleet\e[0m  ⟨5,5,5⟩ GF(2)      \e[2mthreads\e[0m " + J.to_s() + "   \e[2mround\e[0m " + round.to_s() + "   \e[2melapsed\e[0m " + el.to_s() + "s   \e[2mmoves\e[0m " + moves.to_s()
  << ""
  << "  \e[1;32mfleet best  rank " + fleet_best.to_s() + "\e[0m   \e[2m(+" + gap.to_s() + " to record " + RECORD.to_s() + ")\e[0m      \e[1mops " + best_ops.to_s() + "\e[0m \e[2m(naive " + NAIVE_OPS.to_s() + ")\e[0m   \e[2mbits\e[0m " + best_bitsv.to_s() + "   \e[2mvalid\e[0m " + best_valid.to_s()
  << ""
  if histn > 1
    << "  \e[32mrank " + spark(rankhist, histn, RECORD, 125, 60) + "\e[0m  \e[2m125→" + fleet_best.to_s() + "\e[0m"
    << "  \e[33mops  " + spark(opshist, histn, NAIVE_OPS, opshist[0], 60) + "\e[0m  \e[2m" + opshist[0].to_s() + "→" + best_ops.to_s() + "\e[0m"
  << ""
  << "  \e[2mnew-bests\e[0m " + newbests.to_s() + "    \e[2mreseeds\e[0m " + reseeds.to_s() + "    \e[2mnaive-wraps\e[0m " + naive_wraps.to_s() + "    \e[2mdensity-slack\e[0m " + DSLACK.to_s()
  if GPU == 1
    << "  \e[35mGPU scout\e[0m  relay best " + gpu_seen.to_s() + "   \e[2mcandidates pulled\e[0m " + gpu_pulls.to_s()
  << ""
  << "  \e[36mwalkers (best rank per thread)\e[0m"
  w = 0 ## i64
  line = "   "
  while w < J
    line = line + read_best_rank(sts[w]).to_s() + " "
    if ((w + 1) % 10) == 0
      << line
      line = "   "
    w += 1
  if line.size() > 3
    << line
  << ""
  << "  \e[2mrank → asymptotic exponent (want ↓);  ops → real base-case work (want ↓ too).  Ctrl-C to stop.\e[0m"
  flush()

  # ---- hook: status file every 4 rounds ----
  if (round % 4) == 0
    sbody = "round=" + round.to_s() + " fleet_best=" + fleet_best.to_s() + " ops=" + best_ops.to_s() + " bits=" + best_bitsv.to_s() + " valid=" + best_valid.to_s() + " newbests=" + newbests.to_s() + " reseeds=" + reseeds.to_s() + " naive_wraps=" + naive_wraps.to_s() + " moves=" + moves.to_s() + " elapsed=" + el.to_s() + " dslack=" + DSLACK.to_s() + " gpu_best=" + gpu_seen.to_s() + " gpu_pulls=" + gpu_pulls.to_s() + "\n"
    write_file("flipfleet_status.txt", sbody)

  round += 1
