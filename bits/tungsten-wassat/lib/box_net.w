# Model-only common-net worker. Decode and search are concurrent with CDCL.
# A geometry candidate is never a verdict: complete it against the original
# clauses, replay every clause, then publish the model through the race slot.
use box_net_decode

WASSAT_BOX_NET_WALL_MS = 60000
WASSAT_BOX_NET_FIRST_STEPS = 20000000
WASSAT_BOX_NET_REPAIR_CONFLICTS = 4096
WASSAT_BOX_NET_AUTO_MIN_SQUARES = 58

-> wassat_box_net_shape(nv, nc, n) (i64 i64 i64) i64
  return 0 if n < 8 || n > 64 || (n & 1) != 0
  # Two surface encodings, a compact n*n bijection, and four rotations per
  # primary square. This admits sizes, not known formula hashes or names.
  return 0 if nv != 3*n*n+16*n || nc < 64*n*n || nc > 90*n*n
  1

-> wassat_box_net_bytes(nv, nc) (i64 i64) i64
  64*(nv+1)+32*nc+262144

-> wassat_box_net_plan(formula, config, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_BOX_NET")
  return nil if mode == "0" || System.cpu_count <= workers || System.physical_memory_bytes <= 0
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if wassat_box_net_shape(nv,nc,config.max_clause_size) == 0
  # Smaller surfaces did not benefit in paired portfolio controls. Keep
  # their existing workers unchanged unless this lane is explicitly enabled.
  return nil if config.max_clause_size < WASSAT_BOX_NET_AUTO_MIN_SQUARES && mode != "1"
  scratch = wassat_box_net_bytes(nv,nc)
  # Include one private completion solver as well as decoder/search scratch.
  return nil unless wassat_race_memory_fits?(formula,cdcl+1,sls,pre,extra+scratch)
  fresh_period = 1
  if env("WASSAT_BOX_NET_FRESH_PERIOD") != nil
    fresh_period = wassat_decimal_in_range("WASSAT_BOX_NET_FRESH_PERIOD",env("WASSAT_BOX_NET_FRESH_PERIOD"),1,64)
  {"box_net": true, "meta": i64[32], "decode_meta": i64[32], "scratch": scratch, "fresh_period": fresh_period}

-> wassat_box_net_complete(formula, decoded, state, p, stop, res, base, deadline)
  n = decoded["state"][0]
  mapping = decoded["mapping"]
  rotation = decoded["rotation"]
  assumptions = []
  i = 0
  while i < n
    assumptions.push(mapping[state[192+i]*n+i])
    r = 0
    while r < 4
      v = rotation[4*i+r]
      assumptions.push(state[256+i] == r ? v : -v)
      r += 1
    i += 1
  return 0 if wassat_stop_load(stop) != 0 || clock_ms() >= deadline
  started = clock_ms()
  nv = formula["nvars"]
  solver = Wassat.from_flat(nv,wassat_raw_artifact(formula,nv),WASSAT_PROOF_NONE)
  solver.set_stop_cell(stop)
  result = solver.solve_assuming_budget(assumptions,WASSAT_BOX_NET_REPAIR_CONFLICTS)
  p[9] = result["conflicts"]
  p[6] = clock_ms()-started
  return 0 unless result["sat"]
  return 0 if wassat_stop_load(stop) != 0 || clock_ms() >= deadline
  started = clock_ms()
  model = result["model"]
  return 0 if model.size != nv
  values = i8[nv+1]
  i = 0
  while i < nv
    v = model[i]
    return 0 if v != i+1 && v != -i-1
    values[i+1] = v > 0 ? 1 : 0
    i += 1
  hit = wassat_box_net_replay(formula["flat_lits"],formula["flat_offs"],formula["flat_lens"],nv,formula["flat_ncl"],values,p,stop,deadline)
  p[7] = clock_ms()-started
  return 0 if hit == 0
  i = 1
  while i <= nv
    res[base+i] = values[i]
    i += 1
  1

-> wassat_box_net_arm(formula, plan, stop, res, base, nv)
  p = plan["meta"]
  dm = plan["decode_meta"]
  p[2] = clock_ms()
  deadline = p[2]+WASSAT_BOX_NET_WALL_MS
  res[base+nv+6] = p[2]
  p[27] = plan["scratch"]
  decoded = wassat_box_net_decode(formula,stop,p[2]+1000,dm)
  p[4] = clock_ms()-p[2]
  hit = 0
  if decoded != nil && wassat_stop_load(stop) == 0
    g = decoded["geometry"]
    m = decoded["state"]
    m[30] = plan["fresh_period"]
    p[28] = m[30]
    p[1] = m[0]
    state = i64[4096]
    rng = u64[3]
    rng[0] = 712837
    started = clock_ms()
    candidate = wassat_box_net_search(g,state,m,rng,stop,deadline,WASSAT_BOX_NET_FIRST_STEPS)
    p[13] = m[8]
    if candidate == 0 && m[25] == 0 && m[8] == WASSAT_BOX_NET_FIRST_STEPS
      rng[0] = 853171
      m[8] = 0
      candidate = wassat_box_net_search(g,state,m,rng,stop,deadline,0)
      p[13] += m[8]
    p[5] = clock_ms()-started
    p[8] = candidate
    p[12] = m[25]
    p[14] = m[7]
    p[15] = m[10]
    p[16] = m[26]
    p[17] = m[29]
    p[18] = m[27]
    p[19] = m[28]
    p[20] = m[9]
    p[21] = m[23]
    p[22] = m[15]
    hit = wassat_box_net_complete(formula,decoded,state,p,stop,res,base,deadline) if candidate != 0
  else
    p[12] = dm[7]
  p[23] = dm[8]
  p[24] = dm[1]
  p[25] = dm[4]
  p[26] = dm[5]
  p[3] = clock_ms()
  res[base+nv+5] = p[3]
  res[base+nv+4] = p[9]
  if hit == 1 && wassat_stop_load(stop) == 0 && p[3] < deadline
    p[0] = 1
    z = ccall("__w_arr_store_rel",res,base,1)
    won = wassat_stop_publish(stop,1)
    return 1
  p[12] = 1 if wassat_stop_load(stop) != 0
  p[12] = 2 if p[12] == 0 && p[3] >= deadline
  0

-> wassat_box_net_profile(p)
  wassat_prof_note("race.box_net status=[p[0]] squares=[p[1]] decode_stage=[p[23]] clause_scans=[p[24]] rotation_clauses=[p[25]] coherence_clauses=[p[26]] steps=[p[13]] evaluations=[p[14]] restarts=[p[15]] fresh_period=[p[28]] path_attempts=[p[16]] path_nodes=[p[17]] moves=[p[18]] rejected_moves=[p[19]] best=[p[20]] connected=[p[21]] polls=[p[22]] candidates=[p[8]] repair_conflicts=[p[9]] replay_clauses=[p[10]] replay_literals=[p[11]] stopped=[p[12]] decode_ms=[p[4]] search_ms=[p[5]] repair_ms=[p[6]] replay_ms=[p[7]] scratch_bytes=[p[27]] worker_ms=[p[3]-p[2]]")
