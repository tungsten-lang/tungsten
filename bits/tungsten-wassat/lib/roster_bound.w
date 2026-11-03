# Input-derived order-domain roster bounds. This worker proves original-clause
# sufficiency and a run-counting contradiction, but does not produce DRAT.
# It is admitted only as a spare parallel fast-mode lane; proof mode falls back.
use roster_bound/refuter

# Metrics: 0 stop (1 cancellation, 2 deadline, 3 work cap), 1 polls,
# 2 chain links, 3 domains, 4 candidate root groups, 5 hour-table valuations,
# 6 hour nodes, 7 local clauses, 8 local incidences, 9 exact clause queries,
# 10 hash probes, 11 Boolean valuations, 12 Boolean leaves, 13 days,
# 14 required hours, 15 penalty budget, 16 upper hours, 17 pair weight,
# 18 gap weight, 19 hour candidates, 20 preference candidates,
# 30 scratch bytes, 38 result, 39 milliseconds. Buffers are reused per candidate.
-> wassat_roster_plan(formula, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_ROSTER_BOUND")
  return nil if mode == "0" || System.cpu_count <= workers || wassat_race_round1_conflicts != 0
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return nil if nv < 1 || nv > 1000000 || nc < 1 || nc > 10000000 || nl < 1 || nl > 40000000
  # Constant-size admission only. The original links are checked again in the
  # worker; identifiers and a matching prefix never establish UNSAT.
  if mode != "1"
    return nil if nv < 256 || nc < 1000
    lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
    i = 0; breaks = 0; previous = 0
    while i < 64
      return nil if lens[i] != 2
      o = offs[i]; a = lits[o]; b = lits[o + 1]
      if a > b
        t = a; a = b; b = t
      return nil if a >= 0 || b != 1 - a
      breaks += 1 if 0 - a != previous; previous = b; i += 1
    return nil if breaks < 8
  # Includes all fixed tables, candidate buffers and object/array headers.
  # Existing solvers and their memory reservations are retained unchanged.
  scratch = 134217728 + 112 * (nv + 1) + 4 * nc
  # Like the bounded resource and byte workers, use a six-GiB resident
  # envelope. The generic walker gate is smaller because its arenas grow.
  estimate = wassat_cdcl_arena_bytes(formula) * cdcl
  estimate += wassat_sls_arena_bytes(formula) * sls
  estimate += wassat_preprocess_arena_bytes(formula) * pre + extra + scratch
  memory = System.physical_memory_bytes ## i64
  ceiling = memory / 3; ceiling = 6442450944 if ceiling > 6442450944
  wassat_prof_note("race.roster_plan estimate=[estimate] ceiling=[ceiling] scratch=[scratch]")
  return nil if memory <= 0 || estimate > ceiling
  {"roster_bound": true, "meta": i64[64], "scratch": scratch}

-> wassat_roster_refute(formula, m, stop, deadline = 0)
  return 0 if m.size < 64 || stop.size < 2
  i = 0
  while i < 64
    m[i] = 0; i += 1
  started = clock_ms(); checker = WassatRoster.new(formula, stop, deadline, m)
  result = checker.solve
  m[38] = result; m[39] = clock_ms() - started
  result

-> wassat_roster_arm(formula, m, stop, res, base, nv)
  started = clock_ms(); res[base + nv + 6] = started
  result = wassat_roster_refute(formula, m, stop, started + 10000)
  res[base + nv + 5] = clock_ms()
  if result == -1 && !wassat_stop_requested?(stop)
    z = ccall("__w_arr_store_rel", res, base, -1)
    z = wassat_stop_publish(stop, -1)
  0

-> wassat_roster_profile(m)
  wassat_prof_note("race.roster_bound result=[m[38]] ms=[m[39]] domains=[m[3]] roots=[m[4]] candidates=[m[19]] preferences=[m[20]] hour_values=[m[5]] bool_values=[m[11]] local_clauses=[m[7]] clause_queries=[m[9]] hash_probes=[m[10]] days=[m[13]] required=[m[14]] budget=[m[15]] upper=[m[16]] pair_weight=[m[17]] gap_weight=[m[18]] scratch=[m[30]] stop=[m[0]] polls=[m[1]]")
