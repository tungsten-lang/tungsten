# Large finite-domain model search beside the established solving arms.
# m: status, recognized, stop, domains, preparation clauses/literals,
# restarts, iterations, moves, bumps, candidates, updates, polls, best,
# replay clauses/literals, verified, start/end ms, reset weights,
# preparation ms, reserved bytes, restart iterations, bump incidences,
# root-pruned values, interference edges. No miss is an UNSAT verdict.
use domain_sparse_walk

WASSAT_SPARSE_DOMAIN_STEPS = 5000000
WASSAT_SPARSE_DOMAIN_RESTARTS = 4
WASSAT_SPARSE_DOMAIN_WALL_MS = 30000

-> wassat_sparse_domain_bytes(nv,nc) (i64 i64) i64
  # Two CSR incidences and one weight per binary, plus every preparation
  # and search array even if the compiler retains them until worker exit.
  24*nc + 128*(nv+2) + 2097152

-> wassat_sparse_domain_memory_allowed(estimate,memory) (i64 i64) i64
  return 0 if estimate < 0 || memory <= 0
  ceiling = memory / 3
  ceiling = 6442450944 if ceiling > 6442450944
  estimate <= ceiling ? 1 : 0

-> wassat_sparse_domain_plan(f,config,workers,cdcl,sls,pre,extra)
  mode = env("WASSAT_SPARSE_DOMAIN")
  return nil if mode == "0" || env("WASSAT_DOMAIN_WALK") == "0"
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0 || System.cpu_count <= workers
  nv = f["nvars"]; nc = f["flat_ncl"]
  return nil if nv <= WASSAT_DOMAIN_MAX_VARS || nv > 100000 || nc < 500 || nc > 4000000
  return nil if config.max_clause_size < 8 || config.max_clause_size > 32
  lits = f["flat_lits"]; offs = f["flat_offs"]; lens = f["flat_lens"]
  return nil if lens[0] < 8 || lens[0] > 32
  j = 0
  while j < lens[0]
    return nil if lits[offs[0]+j] <= 0
    j += 1
  binary = 0; ci = 1; limit = nc < 512 ? nc : 512
  while ci < limit
    if lens[ci] == 2 && lits[offs[ci]] < 0 && lits[offs[ci]+1] < 0
      binary += 1
    ci += 1
  return nil if binary*4 < limit*3
  scratch = wassat_sparse_domain_bytes(nv,nc)
  estimate = cdcl*wassat_cdcl_arena_bytes(f) + sls*wassat_sls_arena_bytes(f)
  estimate += pre*wassat_preprocess_arena_bytes(f) + extra + scratch
  return nil if wassat_sparse_domain_memory_allowed(estimate,System.physical_memory_bytes) == 0
  { "sparse_domain": true, "meta": i64[32], "scratch": scratch }

-> wassat_sparse_domain_verify(lits,offs,lens,nc,owner,sol,m,stop,deadline) (i64[] i64[] i64[] i64 i32[] i32[] i64[] i64[] i64) i64
  ci = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
    j = 0; ok = false
    while j < lens[ci]
      lit = lits[offs[ci]+j]; v = lit < 0 ? -lit : lit
      chosen = sol[owner[v]-1] == v
      ok = true if (lit > 0 && chosen) || (lit < 0 && !chosen)
      j += 1; m[15] += 1
    return 0 unless ok
    ci += 1; m[14] += 1
  m[16] = 1
  1

-> wassat_sparse_domain_run(f,m,stop,res,base,deadline,restarts,steps)
  return 0 if restarts < 1 || restarts > 16 || steps < 1 || steps > 10000000
  start = clock_ms(); prep_deadline = start+1000
  prep_deadline = deadline if deadline > 0 && deadline < prep_deadline
  d = wassat_sparse_domain_prepare(f,m,stop,prep_deadline); m[20] = clock_ms()-start
  return 0 if d == nil
  owner = d["owner"]; values = d["values"]; first = d["first"]; allowed = d["allowed"]
  heads = d["heads"]; edges = d["edges"]; ids = d["ids"]; nb = d["nb"]; nv = d["nv"]
  sol = i32[nb]; counts = i32[nv+1]; costs = i64[nv+1]; weights = i32[d["ne"]]
  bad = i32[nb]; pos = i32[nb]; st = i64[4]; m[13] = d["ne"]; attempt = 1
  while attempt <= restarts
    return 0 if wassat_sparse_domain_poll(m,stop,deadline) != 0
    m[6] = attempt
    hit = wassat_sparse_domain_trial(owner,values,first,allowed,heads,edges,ids,
      sol,counts,costs,weights,bad,pos,st,m,stop,nv,nb,attempt,steps,deadline)
    if hit == 1
      valid = wassat_sparse_domain_verify(f["flat_lits"],f["flat_offs"],f["flat_lens"],f["flat_ncl"],owner,sol,m,stop,deadline)
      return 0 unless valid == 1
      v = 1
      while v <= nv
        return 0 if (v & 4095) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
        res[base+v] = sol[owner[v]-1] == v ? 1 : 0; v += 1
      return 1
    return 0 if m[2] != 0
    attempt += 1
  m[2] = 3
  0

-> wassat_sparse_domain_arm(f,plan,stop,res,base,nv)
  m = plan["meta"]; m[17] = clock_ms(); m[21] = plan["scratch"]
  res[base+nv+6] = m[17]
  hit = wassat_sparse_domain_run(f,m,stop,res,base,m[17]+WASSAT_SPARSE_DOMAIN_WALL_MS,
    WASSAT_SPARSE_DOMAIN_RESTARTS,WASSAT_SPARSE_DOMAIN_STEPS)
  m[18] = clock_ms(); res[base+nv+5] = m[18]
  if hit == 1 && wassat_sparse_domain_poll(m,stop,m[17]+WASSAT_SPARSE_DOMAIN_WALL_MS) == 0
    m[0] = 1
    z = ccall("__w_arr_store_rel",res,base,1)
    z = wassat_stop_publish(stop,1)
    return 1
  0

-> wassat_sparse_domain_profile(m)
  wassat_prof_note("race.sparse_domain status=[m[0]] recognized=[m[1]] stopped=[m[2]] domains=[m[3]] prep_clauses=[m[4]] prep_literals=[m[5]] restarts=[m[6]] iterations=[m[7]] moves=[m[8]] bumps=[m[9]] candidates=[m[10]] updates=[m[11]] polls=[m[12]] best_violations=[m[13]] replay_clauses=[m[14]] replay_literals=[m[15]] verified=[m[16]] reset_weights=[m[19]] prepare_ms=[m[20]] scratch_bytes=[m[21]] restart_iterations=[m[22]] bump_incidences=[m[23]] root_pruned=[m[24]] edges=[m[25]] ms=[m[18]-m[17]]")
