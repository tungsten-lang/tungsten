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
GSEED_EVERY = 200 ## i64     # --gpu-seed-every: rounds between GPU seed refreshes (a
                             # rank record refreshes immediately regardless)
# Restart-free live sweep: ramp ONE param over time in a single relay process.
SWEEP_PARAM = ""             # --gpu-sweep <steps|reseed|margin|workq|wanderq|wthr>
SWEEP_LO = 3 ## i64          # --sweep-lo
SWEEP_HI = 15 ## i64         # --sweep-hi
SWEEP_STEP = 2 ## i64        # --sweep-step
SWEEP_DWELL = 40 ## i64      # --sweep-dwell  : seconds of fresh descent per value
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
  if a == "--gpu-seed-every"
    if ai + 1 < av.size()
      GSEED_EVERY = av[ai + 1].to_i()
  if a == "--gpu-sweep"
    GPU = 1
    GPU_ONLY = 1
    if ai + 1 < av.size()
      SWEEP_PARAM = av[ai + 1]
  if a == "--sweep-lo"
    if ai + 1 < av.size()
      SWEEP_LO = av[ai + 1].to_i()
  if a == "--sweep-hi"
    if ai + 1 < av.size()
      SWEEP_HI = av[ai + 1].to_i()
  if a == "--sweep-step"
    if ai + 1 < av.size()
      SWEEP_STEP = av[ai + 1].to_i()
  if a == "--sweep-dwell"
    if ai + 1 < av.size()
      SWEEP_DWELL = av[ai + 1].to_i()
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
# fleet_best/fleet_best_den = the best (rank, density) EVER seen (monotonic; it
# survives a fleet-wide sawtooth wrap, and is what we log/seed the GPU from).
fleet_best = 999 ## i64
fleet_best_den = 999999999 ## i64
best_ops = 0 ## i64
best_bitsv = 0 ## i64
best_valid = 1 ## i64
# cur_rank = the elite's CURRENT best rank (the decomposition the fleet is working
# right now; jumps back to naive after a wrap). gband = the global band = the
# elite's band, which every explorer follows. band_moves/rank_moves = per-thread
# moves spent at the current band / current rank (for the TUI).
cur_rank = 999 ## i64
gband = 1 ## i64
prev_gband = 0 ## i64
band_moves = 0 ## i64
rank_moves = 0 ## i64
prev_rank = 999 ## i64
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
GLIVE = "ff_gpu_live.txt"
gpu_seen = 999 ## i64
gpu_pulled = 999 ## i64
gpu_pulled_den = 999999999 ## i64
gpu_pulls = 0 ## i64
if GPU == 1
  zp = system("pwd > .ff_cwd.tmp 2>/dev/null")
  cwdc = read_file(".ff_cwd.tmp")
  cwd = "."
  if cwdc != nil
    cwd = cwdc.split("\n")[0]
  GSEED = cwd + "/ff_gpu_seed.txt"
  GBEST = cwd + "/ff_gpu_best.txt"
  GLIVE = cwd + "/ff_gpu_live.txt"
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
  # Spawn detached, wrapped in a watchdog: $PPID = this flipfleet; when we exit
  # (Ctrl+C, kill, crash), the watchdog reaps the relay so no GPU process is left.
  gcmd = "FF=$PPID; ( cd " + root + "; ./benchmarks/matmul/gpu_relay " + GSEED + " " + GBEST + " 5 5 5" + hp + " " + GLIVE + " > " + glog + " 2>&1 & R=$!; while kill -0 $FF 2>/dev/null; do sleep 3; done; kill $R 2>/dev/null ) &"
  zs = system(gcmd)
  << "  GPU relay spawned as candidate scout (log: " + glog + "). first descent ~15-30s (Metal compile). stop with: pkill gpu_relay"
  flush()

# ---- --gpu-sweep: ramp ONE param live in a single relay process (no restarts). Each
# value gets a fresh descent (naive seed + new generation -> relay force-reseeds). ----
if SWEEP_PARAM != ""
  << "  LIVE SWEEP of '" + SWEEP_PARAM + "' " + SWEEP_LO.to_s() + "->" + SWEEP_HI.to_s() + " step " + SWEEP_STEP.to_s() + ", " + SWEEP_DWELL.to_s() + "s/value (one relay, no restarts). results -> ff_gpu_sweep.txt"
  flush()
  results = "param=" + SWEEP_PARAM + "\n"
  gen = 0 ## i64
  V = SWEEP_LO ## i64
  while V <= SWEEP_HI
    gen += 1
    sv_steps = GSTEPS ## i64
    sv_reseed = GRESEED ## i64
    sv_margin = GMARGIN ## i64
    sv_workq = GWORKQ ## i64
    sv_wanderq = GWANDERQ ## i64
    sv_wthr = GWTHR ## i64
    if SWEEP_PARAM == "steps"
      sv_steps = V
    if SWEEP_PARAM == "reseed"
      sv_reseed = V
    if SWEEP_PARAM == "margin"
      sv_margin = V
    if SWEEP_PARAM == "workq"
      sv_workq = V
    if SWEEP_PARAM == "wanderq"
      sv_wanderq = V
    if SWEEP_PARAM == "wthr"
      sv_wthr = V
    ds3 = dump_scheme(sts[0], GSEED)
    liveline = sv_steps.to_s() + " " + sv_reseed.to_s() + " " + sv_margin.to_s() + " " + sv_workq.to_s() + " " + sv_wanderq.to_s() + " " + sv_wthr.to_s() + " " + gen.to_s() + "\n"
    zl = write_file(GLIVE, liveline)
    # handshake: wait until the relay logs it applied this generation (reseeded from
    # naive with the new value) — covers Metal compile + long rounds. Then discard any
    # stale in-flight best so the dwell measures only this value's fresh descent.
    tag = "gen=" + gen.to_s() + " "
    hw = 0 ## i64
    while hw < 60
      lgc = read_file(glog)
      if lgc != nil
        if lgc.include?(tag)
          hw = 900
      if hw < 900
        zzh = ccall("w_thread_sleep_ms", 1000)
        hw += 1
    zc3 = write_file(GBEST, "")
    bestv = 999 ## i64
    # el2 counts elapsed; the SWEEP_DWELL measurement window only STARTS once the fresh
    # descent produces its first write (absorbs GPU round latency — a single dispatch of
    # big STEPS can exceed the dwell). Hard cap so a dead relay can't stall the sweep.
    started = 0 ## i64
    dstart = 0 ## i64
    el2 = 0 ## i64
    cap2 = SWEEP_DWELL + 120 ## i64
    while el2 < cap2
      gc2 = read_file(GBEST)
      if gc2 != nil
        gl2 = gc2.split("\n")
        if gl2.size() > 0
          gr2 = gl2[0].to_i()
          if gr2 > 0
            if gr2 < bestv
              bestv = gr2
            if started == 0
              started = 1
              dstart = el2
      phase = "warming up (reseed + first dispatch)..."
      if started == 1
        phase = "measuring " + (el2 - dstart).to_s() + "/" + SWEEP_DWELL.to_s() + "s"
      << "\e[H\e[2J"
      << "\e[1;35m  flipfleet live-sweep\e[0m  ⟨5,5,5⟩ GF(2)    \e[2mparam\e[0m " + SWEEP_PARAM + "    \e[2mvalue\e[0m " + V.to_s()
      << ""
      if bestv == 999
        << "  \e[2m" + phase + "\e[0m"
      else
        << "  \e[1;32mbest this value  rank " + bestv.to_s() + "\e[0m   \e[2m(record " + RECORD.to_s() + ")   " + phase + "\e[0m"
      << ""
      << "  \e[36mresults so far\e[0m"
      << results
      << "  \e[2mCtrl-C to stop.\e[0m"
      flush()
      zzz2 = ccall("w_thread_sleep_ms", 2000)
      el2 += 2
      if started == 1
        if (el2 - dstart) >= SWEEP_DWELL
          el2 = cap2
    results = results + SWEEP_PARAM + "=" + V.to_s() + " gpu_best=" + bestv.to_s() + "\n"
    zr = write_file("ff_gpu_sweep.txt", results)
    V += SWEEP_STEP
  << "\e[H\e[2J"
  << "LIVE SWEEP DONE — results (also in ff_gpu_sweep.txt):"
  << results
  flush()
  round = 2000000000

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
    zzz = ccall("w_thread_sleep_ms", 2000)   # NOT system("sleep") — that masks SIGINT (Ctrl+C)
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

  # ---- ONE coordinated searcher. Walker 0 is the ELITE/leader: it carries the
  # sawtooth, holds the current-best decomposition, and its band is the global
  # band. Walkers 1..J-1 are EXPLORERS that hammer the elite's decomposition. ----

  # best-of-round over ALL walkers (lexicographic rank, then density)
  bestw = 0 ## i64
  brank = read_best_rank(sts[0]) ## i64
  bden = best_bits(sts[0]) ## i64
  w = 1
  while w < J
    r = read_best_rank(sts[w]) ## i64
    d = best_bits(sts[w]) ## i64
    better = 0 ## i64
    if r < brank
      better = 1
    if r == brank
      if d < bden
        better = 1
    if better == 1
      brank = r
      bden = d
      bestw = w
    w += 1

  # if an explorer beat the elite, the elite ADOPTS it — this resets the elite's
  # sawtooth to band 1, exactly like an in-place descent would. reseed_from arms
  # nextesc to the short naive-init budget (100M); re-arm it to a full work-zone
  # dwell (2.5B) so the band holds at 1 for 2.5B moves at the adopted rank before
  # escalating, exactly as an in-place descent (walk_worker) does.
  if bestw != 0
    z = reseed_from(sts[0], sts[bestw], round * 131 + 7)
    sts[0][10091 + 7] = sts[0][10091 + 6] + 500000000
    reseeds += 1
  cur_rank = read_best_rank(sts[0])
  cur_den = best_bits(sts[0]) ## i64
  gband = sts[0][10091 + 3]

  # best-ever bookkeeping (monotonic; survives a fleet wrap). This is the record
  # we show, log, and (with --gpu) seed the density scout from.
  everbetter = 0 ## i64
  rank_record = 0 ## i64
  if cur_rank < fleet_best
    everbetter = 1
    rank_record = 1
  if cur_rank == fleet_best
    if cur_den < fleet_best_den
      everbetter = 1
  if everbetter == 1
    fleet_best = cur_rank
    fleet_best_den = cur_den
    best_bitsv = cur_den
    best_ops = cur_den - cur_rank - OUTPUTS
    best_valid = verify_best(sts[0])
    newbests += 1

  # fleet-wide sawtooth wrap: when the leader's sawtooth exhausts (CYCLEOUT), the
  # WHOLE fleet abandons this decomposition and restarts from fresh naive seeds.
  wrapped = 0 ## i64
  if read_cycled(sts[0]) == 1
    w = 0
    while w < J
      z = init_naive(sts[w], round * 977 + w * 13 + 1, DSLACK, CYCLES)
      w += 1
    naive_wraps += 1
    gband = 1
    wrapped = 1
  else
    # explorers reseed onto the leader's best EVERY round (full force on one seed),
    # at the leader's band (follow-the-leader).
    w = 1
    while w < J
      z = reseed_from(sts[w], sts[0], round * 263 + w * 17 + 3)
      sts[w][10091 + 3] = gband
      reseeds += 1
      w += 1
  cur_rank = read_best_rank(sts[0])

  # ---- per-thread move counters (moves spent at the current band / rank) ----
  if gband != prev_gband
    band_moves = 0
  else
    band_moves = band_moves + STEPS
  prev_gband = gband
  if cur_rank < prev_rank
    rank_moves = 0
  else
    rank_moves = rank_moves + STEPS
  prev_rank = cur_rank

  # ---- GPU scout: re-seed it from the record only on a new rank record (immediate)
  # or a periodic refresh (every GSEED_EVERY rounds), NOT on every density tweak —
  # that thrashed the relay's seed. Then pull any lexicographically better candidate
  # it returns into an explorer to be adopted. ----
  if GPU == 1
    do_dump = 0 ## i64
    if rank_record == 1
      do_dump = 1
    if (round % GSEED_EVERY) == 0
      if wrapped == 0
        do_dump = 1
    if do_dump == 1
      if fleet_best < 999
        gd = dump_scheme(sts[0], GSEED)
    gc = read_file(GBEST)
    grank = 0 ## i64
    gden = 0 ## i64
    if gc != nil
      gl = gc.split("\n")
      if gl.size() > 0
        l0 = gl[0].split(" ")
        grank = l0[0].to_i()
        if l0.size() > 1
          gden = l0[1].to_i()
    gpu_seen = grank
    if grank > 0
      # pull if the GPU candidate is lexicographically better than the fleet best
      # (lower rank, or same rank at lower density) AND we have not already pulled it
      glex = 0 ## i64
      if grank < fleet_best
        glex = 1
      if grank == fleet_best
        if gden > 0
          if gden < fleet_best_den
            glex = 1
      fresh = 0 ## i64
      if grank < gpu_pulled
        fresh = 1
      if grank == gpu_pulled
        if gden < gpu_pulled_den
          fresh = 1
      if glex == 1
        if fresh == 1
          # overwrite the least-valuable walker (highest rank, then highest density)
          worstw = 0 ## i64
          worstr = 0 ## i64
          worstd = 0 ## i64
          w = 0
          while w < J
            rr = read_best_rank(sts[w]) ## i64
            dd = best_bits(sts[w]) ## i64
            wbetter = 0 ## i64
            if rr > worstr
              wbetter = 1
            if rr == worstr
              if dd > worstd
                wbetter = 1
            if wbetter == 1
              worstr = rr
              worstd = dd
              worstw = w
            w += 1
          lr = load_scheme(sts[worstw], GBEST, round * 271 + 3)
          if verify_best(sts[worstw]) == 1
            gpu_pulls += 1
            gpu_pulled = grank
            gpu_pulled_den = gden

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
  moves = round * J * STEPS ## i64   # TOTAL moves across all J threads
  band_budget = 500000000 ## i64     # work-zone dwell per band (per-thread)
  if gband > sts[0][10091 + 4]
    band_budget = 100000000          # wander-zone dwell per band
  el = (clock - start).to_i() ## i64

  # ---- TUI: redraw in place ----
  << "\e[H\e[2J"
  << "\e[1;33m  flipfleet\e[0m  ⟨5,5,5⟩ GF(2)      \e[2mthreads\e[0m " + J.to_s() + "   \e[2mround\e[0m " + round.to_s() + "   \e[2melapsed\e[0m " + el.to_s() + "s   \e[2mmoves\e[0m " + (moves / 1000000000).to_s() + "." + ((moves / 100000000) % 10).to_s() + "B"
  << ""
  << "  \e[1;32mfleet best  rank " + fleet_best.to_s() + "\e[0m   \e[2m(+" + gap.to_s() + " to record " + RECORD.to_s() + ")\e[0m      \e[1mops " + best_ops.to_s() + "\e[0m \e[2m(naive " + NAIVE_OPS.to_s() + ")\e[0m   \e[2mbits\e[0m " + best_bitsv.to_s() + "   \e[2mvalid\e[0m " + best_valid.to_s()
  << "  \e[36mleader\e[0m  working rank " + cur_rank.to_s() + "    \e[2mband\e[0m " + gband.to_s() + "    \e[2mmoves@band\e[0m " + (band_moves / 1000000).to_s() + "M/" + (band_budget / 1000000).to_s() + "M    \e[2mmoves@rank\e[0m " + (rank_moves / 1000000).to_s() + "M"
  << ""
  if histn > 1
    << "  \e[32mrank " + spark(rankhist, histn, RECORD, 125, 60) + "\e[0m  \e[2m125→" + fleet_best.to_s() + "\e[0m"
    << "  \e[33mops  " + spark(opshist, histn, NAIVE_OPS, opshist[0], 60) + "\e[0m  \e[2m" + opshist[0].to_s() + "→" + best_ops.to_s() + "\e[0m"
  << ""
  << "  \e[2mnew-bests\e[0m " + newbests.to_s() + "    \e[2mreseeds\e[0m " + reseeds.to_s() + "    \e[2mnaive-wraps\e[0m " + naive_wraps.to_s() + "    \e[2mdensity-slack\e[0m " + DSLACK.to_s()
  if GPU == 1
    << "  \e[35mGPU scout\e[0m  relay best " + gpu_seen.to_s() + "   \e[2mcandidates pulled\e[0m " + gpu_pulls.to_s()
  << ""
  << "  \e[36mwalkers (best rank per thread; w0 = leader, rest hammer its decomposition)\e[0m"
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
    sbody = "round=" + round.to_s() + " fleet_best=" + fleet_best.to_s() + " ops=" + best_ops.to_s() + " bits=" + best_bitsv.to_s() + " valid=" + best_valid.to_s() + " cur_rank=" + cur_rank.to_s() + " band=" + gband.to_s() + " moves_at_band=" + band_moves.to_s() + " moves_at_rank=" + rank_moves.to_s() + " newbests=" + newbests.to_s() + " reseeds=" + reseeds.to_s() + " naive_wraps=" + naive_wraps.to_s() + " moves=" + moves.to_s() + " elapsed=" + el.to_s() + " dslack=" + DSLACK.to_s() + " gpu_best=" + gpu_seen.to_s() + " gpu_pulls=" + gpu_pulls.to_s() + "\n"
    write_file("flipfleet_status.txt", sbody)

  round += 1
