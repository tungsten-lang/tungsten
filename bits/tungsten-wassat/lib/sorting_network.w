# Input-derived comparator search, model-only and parallel to generic CDCL.
# The candidate is completed against a private copy of the original CNF;
# every original clause must pass before the worker can publish SAT.
use sorting_decode

WASSAT_SORTING_WALL_MS = 60000
WASSAT_SORTING_STEPS = 100000000

-> wassat_sorting_bytes(nv, nc, nl) (i64 i64 i64) i64
  # Private literal copy, watch links, trail/signs, decoder DSU and bitplanes.
  8*nl + 8*nc + 64*(nv+1) + 75497472

# Like the bounded byte-relation lane, count retained scouts as well as
# live arms under a six-GiB envelope. The older 2.5-GiB optional-arena gate
# can already be below the unchanged CDCL portfolio's own reservation.
-> wassat_sorting_memory_allowed(estimate, memory) (i64 i64) i64
  return 0 if memory <= 0 || estimate < 0
  budget = memory / 3 ## i64
  budget = 6442450944 if budget > 6442450944
  estimate <= budget ? 1 : 0

-> wassat_sorting_plan(formula, config, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_SORTING")
  return nil if mode == "0" || System.cpu_count <= workers || System.physical_memory_bytes <= 0
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if nv < 16 || nv > 250000 || nc < 16 || nc > 10000000
  return nil if config.max_clause_size < 8 || config.max_clause_size > 16
  lens = formula["flat_lens"]; lits = formula["flat_lits"]; offs = formula["flat_offs"]
  return nil if lens[0] != 2 || lits[offs[0]] >= 0 || lits[offs[0]+1] >= 0
  scratch = wassat_sorting_bytes(nv,nc,formula["flat_nlits"])
  estimate = cdcl*wassat_cdcl_arena_bytes(formula) + sls*wassat_sls_arena_bytes(formula)
  estimate += pre*wassat_preprocess_arena_bytes(formula) + extra + scratch
  return nil if wassat_sorting_memory_allowed(estimate,System.physical_memory_bytes) == 0
  { "sorting_network": true, "meta": i64[32], "scratch": scratch }

# The flat propagator can yield at a consistent watch boundary. Resume it
# in bounded chunks so cancellation does not wait for a full signal cascade.
-> wassat_sorting_propagate(lits, offs, lens, head, links, sign, trail, st, m, stop, deadline, limit) (i64[] i64[] i64[] i32[] i32[] i8[] i32[] i64[] i64[] i64[] i64 i64) i64
  while st[13] < limit
    return -2 if wassat_sorting_poll(m,stop,deadline) != 0
    st[14] = st[13]+65536; st[15] = 0
    rc = wassat_flat_lucky_prop(lits,offs,lens,head,links,sign,trail,st) ## i64
    m[24] = st[13]
    return rc if rc != -2
  m[10] = 3
  -2

-> wassat_sorting_complete(formula, allowed, mate, m, stop, deadline, res, base)
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  original = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  lits = i64[nl]; i = 0
  while i < nl
    return 0 if (i & 16383) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    lits[i] = original[i]; i += 1
  head = i32[2*nv+4]; links = i32[2*nc]
  sign = i8[nv+1]; trail = i32[nv+2]; st = i64[16]
  st[14] = 65536
  rc = wassat_flat_lucky_init(lits,offs,lens,head,links,sign,trail,st,nc,nv)
  if rc == -2
    rc = wassat_sorting_propagate(lits,offs,lens,head,links,sign,trail,st,m,stop,deadline,8*nc+65536)
  return 0 if rc < 0 || wassat_sorting_poll(m,stop,deadline) != 0
  n = m[0]; layer = 0; count = st[1]
  while layer < m[1]
    a = 0
    while a < n
      b = mate[layer*n+a]
      if b > a
        v = allowed[(layer*n+a)*n+b]
        return 0 if v < 1 || v > nv || sign[v] < 0
        if sign[v] == 0
          sign[v] = 1; trail[count] = v; count += 1
      a += 1
    layer += 1
  st[1] = count
  rc = wassat_sorting_propagate(lits,offs,lens,head,links,sign,trail,st,m,stop,deadline,8*nc+65536)
  return 0 if rc < 0
  # Propagation fixes most signal cells. Solve only the compact residual;
  # greedy polarity completion can get stuck on the canonical idle flags.
  remap = i32[nv+1]; remaining = 0; v = 1
  while v <= nv
    if sign[v] == 0
      remaining += 1; remap[v] = remaining
    v += 1
  m[26] = remaining
  return 0 if remaining > 8192
  if remaining > 0
    rnc = 0; rnl = 0; ci = 0
    while ci < nc
      return 0 if (ci & 1023) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
      j = 0; live = 0; satisfied = false
      while j < lens[ci]
        lit = original[offs[ci]+j]; v = wassat_sorting_abs(lit)
        if (lit > 0 && sign[v] > 0) || (lit < 0 && sign[v] < 0)
          satisfied = true
          break
        live += 1 if sign[v] == 0
        j += 1
      unless satisfied
        return 0 if live == 0
        rnc += 1; rnl += live
      ci += 1
    return 0 if rnc > 50000 || rnl > 500000
    m[27] = rnc; m[28] = rnl
    rlits = i64[rnl+1]; roffs = i64[rnc+2]; rlens = i64[rnc+2]
    ri = 0; rc = 0; ci = 0
    while ci < nc
      return 0 if (ci & 1023) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
      j = 0; start = ri; satisfied = false
      while j < lens[ci]
        lit = original[offs[ci]+j]; v = wassat_sorting_abs(lit)
        if (lit > 0 && sign[v] > 0) || (lit < 0 && sign[v] < 0)
          satisfied = true
          break
        j += 1
      unless satisfied
        j = 0
        while j < lens[ci]
          lit = original[offs[ci]+j]; v = wassat_sorting_abs(lit)
          if sign[v] == 0
            return 0 if ri >= rnl
            rlits[ri] = lit > 0 ? remap[v] : -remap[v]; ri += 1
          j += 1
        return 0 if rc >= rnc
        roffs[rc] = start; rlens[rc] = ri-start; rc += 1
      ci += 1
    return 0 if ri != rnl || rc != rnc
    residual = { "nvars": remaining, "flat_ncl": rnc, "flat_nlits": rnl,
      "flat_lits": rlits, "flat_offs": roffs, "flat_lens": rlens,
      "clauses": [], "boxed": false }
    solver = Wassat.from_flat(remaining,wassat_raw_artifact(residual,remaining),WASSAT_PROOF_NONE)
    solver.disable_inprocess; solver.set_stop_cell(stop)
    result = solver.solve_budget(128); attempts = 1
    while result["status"] == 0 && attempts < 32
      return 0 if wassat_sorting_poll(m,stop,deadline) != 0
      result = solver.solve_budget(128); attempts += 1
    m[17] = result["conflicts"]
    return 0 unless result["sat"]
    model = result["model"]; v = 1
    while v <= nv
      if remap[v] > 0
        sign[v] = model[remap[v]-1] > 0 ? 1 : -1
      v += 1
  # Replay the untouched original array, with cancellation between clauses.
  ci = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    j = 0; ok = false
    while j < lens[ci]
      lit = original[offs[ci]+j]
      if (lit > 0 && sign[lit] > 0) || (lit < 0 && sign[-lit] < 0)
        ok = true
        break
      j += 1
    return 0 unless ok
    ci += 1; m[13] += 1
  v = 1
  while v <= nv
    res[base+v] = sign[v] > 0 ? 1 : 0
    v += 1
  m[18] = 1
  1

-> wassat_sorting_arm(formula, plan, stop, res, base, nv)
  m = plan["meta"]
  m[19] = clock_ms(); m[21] = plan["scratch"]
  res[base+nv+6] = m[19]
  deadline = m[19]+WASSAT_SORTING_WALL_MS
  decoded = wassat_sorting_decode(formula,m,stop,m[19]+1000)
  m[14] = clock_ms()-m[19]
  hit = 0
  if decoded != nil && wassat_stop_load(stop) == 0
    allowed = decoded["allowed"]; vectors = decoded["vectors"]
    mate = i8[m[0]*m[1]]; started = clock_ms()
    found = wassat_sorting_search(allowed,vectors,mate,m,stop,deadline,WASSAT_SORTING_STEPS)
    m[15] = clock_ms()-started
    if found != 0 && wassat_sorting_poll(m,stop,deadline) == 0
      started = clock_ms()
      hit = wassat_sorting_complete(formula,allowed,mate,m,stop,deadline,res,base)
      m[16] = clock_ms()-started
  m[20] = clock_ms()
  res[base+nv+5] = m[20]
  if hit == 1 && wassat_sorting_poll(m,stop,deadline) == 0
    z = ccall("__w_arr_store_rel",res,base,1)
    z = wassat_stop_publish(stop,1)
    return 1
  0

-> wassat_sorting_profile(m)
  wassat_prof_note("race.sorting width=[m[0]] depth=[m[1]] selectors=[m[2]] patterns=[m[4]] decode_stage=[m[22]] control_summaries=[m[29]] input_observations=[m[30]] encoded_patterns=[m[31]] clause_scans=[m[5]] literal_visits=[m[23]] moves=[m[6]] accepted=[m[7]] restarts=[m[8]] best=[m[9]] evaluations=[m[12]] polls=[m[11]] stopped=[m[10]] residual_vars=[m[26]] residual_clauses=[m[27]] residual_literals=[m[28]] completion_conflicts=[m[17]] watch_visits=[m[24]] replay_clauses=[m[13]] verified=[m[18]] decode_ms=[m[14]] search_ms=[m[15]] completion_ms=[m[16]] scratch_bytes=[m[21]] worker_ms=[m[20]-m[19]]")
