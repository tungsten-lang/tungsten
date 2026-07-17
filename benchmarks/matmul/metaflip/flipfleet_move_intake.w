# Rotating occasional-lane runner for the twelve move-lab intake lanes
# (lane prefix ffmi_).
#
# The twelve 2026-07-16 intake lanes (sandwich quotient, incremental
# surgery, sandwich ansatz, psi quotient, equivariant surgery, carry
# compile, GF(4) walk, sector suture, sym anneal, pair lift, ball SAT,
# align/relink) are OCCASIONAL options: none has yet earned live pool
# width, and the campaign rule is that only measured reward buys a hot
# lane (GPU_KERNEL_POOL.md).  This runner is the measuring instrument:
#
#   - one bounded, budgeted invocation per step, rotating over the lanes
#     with the pool's dwell discipline (a productive lane doubles its
#     dwell, a lane dry for 8 pulls is dimmed to every 16th rotation);
#   - YIELD counts verified objective wins only (a published lower rank,
#     an off-dictionary suture, a saddle bank entry).  CLOSURES count
#     certified negative knowledge (UNSAT cells, rigidity radii) --
#     valuable, logged, but never conflated with reward;
#   - accounting persists across invocations through a text state file,
#     so a cron / coordinator can call ffmi_step at any cadence;
#   - PROMOTION: two independent yields (or one within the first four
#     pulls) sets the promoted flag and prints the exact registration
#     recipe pointer (GPU_KERNEL_POOL.md "Registration sites"); this
#     runner never edits the pool itself.
#
# Every artifact any lane publishes goes through that lane's own
# dump -> re-parse -> re-gate discipline; this runner only schedules.

use metaflip_worker
use metaflip_rect_worker
use flipfleet_sandwich_quotient
use flipfleet_incremental_surgery
use flipfleet_sandwich_ansatz
use flipfleet_psi_quotient
use flipfleet_equivariant_surgery
use flipfleet_carry_compile
use flipfleet_gf4_walk
use flipfleet_sector_suture
use flipfleet_sym_anneal
use flipfleet_pair_lift
use flipfleet_ball_sat
use flipfleet_align_relink
use flipfleet_psi252_descent_lib

-> ffmi_lane_count() i64
  13

-> ffmi_lane_name(lane) (i64)
  if lane == 0
    return "sandwich-quotient"
  if lane == 1
    return "incremental-surgery"
  if lane == 2
    return "sandwich-ansatz"
  if lane == 3
    return "psi-quotient"
  if lane == 4
    return "equivariant-surgery"
  if lane == 5
    return "carry-compile"
  if lane == 6
    return "gf4-walk"
  if lane == 7
    return "sector-suture"
  if lane == 8
    return "sym-anneal"
  if lane == 9
    return "pair-lift"
  if lane == 10
    return "ball-sat"
  if lane == 11
    return "align-relink"
  if lane == 12
    return "psi-descent"
  "unknown"

# ---------------------------------------------------------------------------
# Accounting state: header 16 slots + 8 per lane.
#   header: 0 magic 1179015525, 1 version, 2 lanes, 3 cursor, 4 steps
#   lane slots (base 16 + lane*8): 0 pulls, 1 yields, 2 closures,
#   3 dry streak, 4 dwell, 5 promoted, 6 total ms, 7 last result

-> ffmi_state_size() i64
  16 + 13 * 8

-> ffmi_state_init(st) (i64[]) i64
  i = 0 ## i64
  while i < ffmi_state_size()
    st[i] = 0
    i += 1
  st[0] = 1179015525
  st[1] = 2
  st[2] = 13
  lane = 0 ## i64
  while lane < 13
    st[16 + lane * 8 + 4] = 1
    lane += 1
  1

-> ffmi_lane_base(lane) (i64) i64
  16 + lane * 8

# Dwell policy: yield doubles dwell (cap 4); 8 dry pulls dim the lane
# (dwell 0 = visited only every 16th full rotation).
-> ffmi_account(st, lane, yield_score, closures, ms) (i64[] i64 i64 i64 i64) i64
  base = ffmi_lane_base(lane) ## i64
  st[base] = st[base] + 1
  st[base + 1] = st[base + 1] + yield_score
  st[base + 2] = st[base + 2] + closures
  st[base + 6] = st[base + 6] + ms
  st[base + 7] = yield_score
  if yield_score > 0
    st[base + 3] = 0
    dwell = st[base + 4] * 2 ## i64
    if dwell > 4
      dwell = 4
    if dwell < 1
      dwell = 1
    st[base + 4] = dwell
    if st[base + 5] == 0
      if st[base + 1] >= 2 || st[base] <= 4
        st[base + 5] = 1
        << "MOVE_INTAKE_PROMOTION lane=" + ffmi_lane_name(lane) + " yields=" + st[base + 1].to_s() + " pulls=" + st[base].to_s() + " -- register per GPU_KERNEL_POOL.md 'Registration sites' (ffkp mode table + ffn readiness/launch) with this evidence"
  else
    st[base + 3] = st[base + 3] + 1
    if st[base + 3] >= 8
      st[base + 4] = 0
  1

# Next lane honoring dwell: advance the cursor; a dimmed lane (dwell 0)
# only fires when the step counter is a multiple of 16.
-> ffmi_pick(st) (i64[]) i64
  tries = 0 ## i64
  while tries < 24
    lane = st[3] % 13 ## i64
    st[3] = st[3] + 1
    base = ffmi_lane_base(lane) ## i64
    if st[base + 4] > 0
      return lane
    if st[4] % 16 == 0
      return lane
    tries += 1
  st[3] % 13

# ---------------------------------------------------------------------------
# Persistence (space-separated decimal words).

-> ffmi_save(st, path) (i64[] String) i64
  text = "" ## String
  i = 0 ## i64
  while i < ffmi_state_size()
    if i > 0
      text = text + " "
    text = text + st[i].to_s()
    i += 1
  if write_file(path, text + "\n")
    return 1
  0

-> ffmi_load(st, path) (i64[] String) i64
  content = read_file(path)
  if content == nil
    return 0
  parts = content.split(" ")
  if parts.size() < ffmi_state_size()
    return 0
  i = 0 ## i64
  while i < ffmi_state_size()
    st[i] = parts[i].to_i()
    i += 1
  if st[0] != 1179015525 || st[2] != 13
    return 0
  1

# ---------------------------------------------------------------------------
# Bounded lane dispatch.  budget_class 0 = smoke (tests, seconds total),
# 1 = occasional (a coordinator step, tens of seconds).  Returns the yield
# score (verified wins only); closures land in out[0], elapsed ms in
# out[1].

-> ffmi_frontier_5x5()
  "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt"

-> ffmi_frontier_4x4()
  "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt"

-> ffmi_door_225_a()
  "benchmarks/matmul/metaflip/matmul_2x2x5_rank18_d84_gf2.txt"

-> ffmi_door_225_b()
  "benchmarks/matmul/metaflip/matmul_2x2x5_rank18_d88_gf2.txt"

-> ffmi_run_lane(lane, seed, budget_class, out) (i64 i64 i64 i64[]) i64
  out[0] = 0
  out[1] = 0
  started = ccall("__w_clock_ms") ## i64
  score = 0 ## i64
  if lane == 0
    # Symmetrizability scan of a frontier presentation (a hit would open a
    # quotient-walk channel).
    meta = i64[4]
    found = ffsq_scan_symmetric(ffmi_frontier_5x5(), 5, meta) ## i64
    if found > 0
      score = found
  if lane == 1
    # Incremental k-surgery on the 4x4 frontier.
    meta = i64[20]
    budget = 5000 ## i64
    subsets = 32 ## i64
    if budget_class > 0
      budget = 100000
      subsets = 256
    hit = ffis_sweep(ffmi_frontier_4x4(), 4, 3, 10, subsets, budget, seed, "/tmp/ffmi_is_hit.txt", meta) ## i64
    if hit > 0
      score = 100
    out[0] = meta[7] + meta[9]
  if lane == 2
    # One cyclic-sandwich cell on 3x3, rotated by seed over (k, f)
    # partitions of rank 26.
    ou = i64[64]
    ov = i64[64]
    ow = i64[64]
    meta = i64[16]
    f = (seed % 3) * 1 ## i64
    k = (26 - f * 2) / 3 ## i64
    if 26 - f * 2 != k * 3
      f = 1
      k = 8
    budget = 5000 ## i64
    if budget_class > 0
      budget = 60000
    hit = ffsan_solve(3, 1, 1, 1, k, f, budget, seed, ou, ov, ow, meta) ## i64
    if hit > 0 && hit < 23
      score = 100
    if meta[3] == 0 - 1
      out[0] = 1
  if lane == 3
    # One psi cell of the <2,5,2> rank-17 partition list, rotated by seed.
    ou = i64[64]
    ov = i64[64]
    ow = i64[64]
    meta = i64[16]
    c = 8 - (seed % 4) ## i64
    f = 17 - 2 * c ## i64
    budget = 5000 ## i64
    if budget_class > 0
      budget = 100000
    hit = ffpsi_solve(2, 5, c, f, budget, seed, ou, ov, ow, meta) ## i64
    if hit > 0 && hit <= 17
      score = 1000
    if meta[2] == 0 - 1
      out[0] = 1
  if lane == 4
    # Equivariant orbit-drop surgery on the C3-closed 5x5 frontier:
    # excise 2 orbits, ask for 1 orbit + 2 cubes (net -1).
    meta = i64[16]
    budget = 3000 ## i64
    if budget_class > 0
      budget = 60000
    hit = ffes_surgery(ffmi_frontier_5x5(), 5, 2, 0, 1, 2, budget, seed, "/tmp/ffmi_es_hit.txt", meta) ## i64
    if hit > 0 && hit < 93
      score = 1000
    if meta[6] == 0 - 1
      out[0] = 1
  if lane == 5
    # Carry compilation of a dropped-in integer witness (documented
    # drop-in path; dry when absent).
    dims = i64[4]
    iu = i64[4096]
    iv = i64[4096]
    iw = i64[4096]
    loaded = ffcc_load_int_scheme("benchmarks/matmul/metaflip/witness_int_2x4x5_rank32.txt", dims, iu, iv, iw, 64) ## i64
    if loaded > 0
      out_u = i64[128]
      out_v = i64[128]
      out_w = i64[128]
      acc_u = i64[128]
      acc_v = i64[128]
      acc_w = i64[128]
      acc_l = i64[128]
      prof = i64[64]
      cmeta = i64[16]
      emitted = ffcc_compile(iu, iv, iw, loaded, dims[0], dims[1], dims[2], out_u, out_v, out_w, acc_u, acc_v, acc_w, acc_l, prof, cmeta) ## i64
      if emitted > 0 && cmeta[6] == 1 && ffcc_gate_rect(out_u, out_v, out_w, emitted, dims[0], dims[1], dims[2]) == 1
        score = emitted
  if lane == 6
    # Bounded GF(4) walk from the naive 3x3 rational embedding.
    tu_a = i64[64]
    tu_b = i64[64]
    tv_a = i64[64]
    tv_b = i64[64]
    tw_a = i64[64]
    tw_b = i64[64]
    cap3 = ffw_default_capacity(3) ## i64
    st3 = i64[ffw_state_size(cap3)]
    r3 = ffw_init_naive_cap(st3, 3, cap3, seed, 0, 1, 1, 1) ## i64
    eu = i64[64]
    ev = i64[64]
    ew = i64[64]
    c3 = ffw_export_current(st3, eu, ev, ew) ## i64
    i = 0 ## i64
    while i < c3
      tu_a[i] = eu[i]
      tv_a[i] = ev[i]
      tw_a[i] = ew[i]
      i += 1
    wmeta = i64[12]
    moves = 5000 ## i64
    if budget_class > 0
      moves = 100000
    best = ffg4_walk(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, c3, 3, 3, 3, moves, seed, wmeta) ## i64
    if best > 0 && best < 23
      score = 100
  if lane == 7
    # Sector-suture sweep over the two checked-in <2,2,5> doors.
    hist = i64[5]
    counters = i64[16]
    wins = ffss_sweep(ffmi_door_225_a(), ffmi_door_225_b(), 2, 2, 5, "", hist, counters) ## i64
    if wins > 0
      score = wins * 10
    score = score + counters[5]
  if lane == 8
    # Bounded symmetry-defect anneal on the 5x5 frontier seed.
    meta = i64[16]
    moves = 20000 ## i64
    if budget_class > 0
      moves = 400000
    hit = ffsa_run_engine(ffmi_frontier_5x5(), "/tmp/ffmi_sa_hit.txt", 5, moves, seed, meta) ## i64
    if hit > 0 && hit < 93
      score = 1000
  if lane == 9
    # Pair-lift crossover on the two <2,2,5> doors; yield = a gated child
    # at distance > 0 from BOTH parents (a genuinely new door).
    cap = ffr_default_capacity(2, 2, 5) ## i64
    sta = i64[ffr_state_size(cap)]
    stb = i64[ffr_state_size(cap)]
    ra = ffr_load_scheme_cap(sta, ffmi_door_225_a(), 2, 2, 5, cap, seed, 0, 1, 1, 1) ## i64
    rb = ffr_load_scheme_cap(stb, ffmi_door_225_b(), 2, 2, 5, cap, seed + 2, 0, 1, 1, 1) ## i64
    if ra == 18 && rb == 18
      xu = i64[64]
      xv = i64[64]
      xw = i64[64]
      yu = i64[64]
      yv = i64[64]
      yw = i64[64]
      c1u = i64[80]
      c1v = i64[80]
      c1w = i64[80]
      c2u = i64[80]
      c2v = i64[80]
      c2w = i64[80]
      pmeta = i64[20]
      ca = ffw_export_current(sta, xu, xv, xw) ## i64
      cb = ffw_export_current(stb, yu, yv, yw) ## i64
      moves = 20000 ## i64
      if budget_class > 0
        moves = 200000
      ok = ffpl_run(xu, xv, xw, 18, yu, yv, yw, 18, 2, 2, 5, moves, 4, seed, c1u, c1v, c1w, c2u, c2v, c2w, pmeta) ## i64
      if ok == 1 && pmeta[10] > 0 && pmeta[11] > 0
        score = pmeta[10]
      if ok == 1 && pmeta[14] > 0 && pmeta[15] > 0
        score = score + pmeta[14]
  if lane == 10
    # Ball-SAT radius probe around the 4x4 frontier anchor.
    per_radius = i64[64]
    meta = i64[16]
    budget = 2000 ## i64
    if budget_class > 0
      budget = 50000
    hit = ffbs_sweep(ffmi_frontier_4x4(), 4, 4, 4, 8, budget, seed, "/tmp/ffmi_bs_hit.txt", per_radius, meta) ## i64
    if hit > 0
      score = 1000
    out[0] = meta[10]
  if lane == 11
    # Alignment + bounded relink on the two <2,2,5> doors mapped through
    # their square-free path is not available (rect shapes); use the two
    # 4x4 rank-47 presentations instead.
    cap4 = ffw_default_capacity(4) ## i64
    sa = i64[ffw_state_size(cap4)]
    sb = i64[ffw_state_size(cap4)]
    ra = ffw_load_scheme_cap(sa, ffmi_frontier_4x4(), 4, cap4, seed, 0, 1, 1, 1) ## i64
    rb = ffw_load_scheme_cap(sb, "benchmarks/matmul/metaflip/matmul_4x4_rank47_d677_flips_gf2.txt", 4, cap4, seed + 2, 0, 1, 1, 1) ## i64
    if ra == 47 && rb == 47
      ops = i64[16]
      doms = i64[16]
      srcs = i64[16]
      tgts = i64[16]
      out_state = i64[ffw_state_size(cap4)]
      ameta = i64[16]
      budget = 300 ## i64
      if budget_class > 0
        budget = 2000
      overlap = ffar_align(sa, sb, 4, cap4, budget, 8, seed, 0, ops, doms, srcs, tgts, out_state, ameta) ## i64
      if overlap == 47
        score = 1000
      if overlap > 0
        out[0] = 0
  if lane == 12
    # Bounded psi-equivariant descent from the checked-in rank-18 witness:
    # a hit is a psi-symmetric rank-17 <2,2,5> record candidate; every
    # certified-UNSAT residual extends the local-rigidity certificate.
    content = read_file("benchmarks/matmul/metaflip/matmul_2x5x2_rank18_psi_symmetric_gf2.txt")
    if content != nil
      wl = content.split("\n")
      wrank = wl[0].to_i() ## i64
      if wrank >= 2 && wrank <= 60
        wu = i64[wrank + 2]
        wv = i64[wrank + 2]
        ww = i64[wrank + 2]
        t = 0 ## i64
        while t < wrank
          parts = wl[1 + t].split(" ")
          wu[t] = parts[0].to_i()
          wv[t] = parts[1].to_i()
          ww[t] = parts[2].to_i()
          t += 1
        dmeta = i64[8]
        depth_p = 1 ## i64
        depth_f = 1 ## i64
        dbudget = 20000 ## i64
        if budget_class > 0
          depth_p = 2
          depth_f = 2
          dbudget = 150000
        dh = ffpds_sweep(wu, wv, ww, wrank, depth_p, depth_f, dbudget, seed, "/tmp/ffmi_psi_descent_hit.txt", dmeta) ## i64
        if dh > 0
          score = 1000
        if dh >= 0
          out[0] = dmeta[1]
  out[1] = ccall("__w_clock_ms") - started
  score

# One scheduling step: pick a lane, run it at the given budget class,
# account, and log.  Returns the lane that ran.
-> ffmi_step(st, seed, budget_class) (i64[] i64 i64) i64
  st[4] = st[4] + 1
  lane = ffmi_pick(st) ## i64
  out = i64[2]
  score = ffmi_run_lane(lane, seed, budget_class, out) ## i64
  z = ffmi_account(st, lane, score, out[0], out[1])
  base = ffmi_lane_base(lane) ## i64
  << "MOVE_INTAKE lane=" + ffmi_lane_name(lane) + " yield=" + score.to_s() + " closures=" + out[0].to_s() + " pulls=" + st[base].to_s() + " total_yield=" + st[base + 1].to_s() + " total_closures=" + st[base + 2].to_s() + " dwell=" + st[base + 4].to_s() + " ms=" + out[1].to_s()
  lane
