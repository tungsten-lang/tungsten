# Infer minimum demands and resource choices from the original clauses. A
# domain component exceeding its resource-slot capacity is only accepted after
# all minimum-counter recurrences and every event incompatibility are checked.
# Unsupported encodings, work limits, deadlines and cancellation return UNKNOWN.
# This fast-mode worker does not emit a monolithic DRAT certificate.
use resource_capacity/decoder
use resource_capacity/discovery
use resource_capacity/verify

# Counters: 0 groups, 1 slots, 2 lower-chain visits, 3 candidate choices,
# 4 conjunctions, 5 domains, 6 proposed resources, 7 witness courses,
# 8 demand, 9 capacity, 10 witness resources, 11 stop, 12 polls,
# 14 proved event pairs, 15 implication work, 16/17 binary graph sizes,
# 18 candidate pair visits, 38 verdict and 39 elapsed milliseconds.

-> wassat_resource_plan(formula, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_RESOURCE_CAPACITY")
  return nil if mode == "0" || System.cpu_count <= workers || wassat_race_round1_conflicts != 0
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return nil if nv < 1 || nv > 1000000 || nc < 1 || nc > 5000000 || nl > 20000000
  # Constant-size prefix screen for grouped occupancy implications. It merely
  # limits admission; all large allocations and exact recognition run in-thread.
  if mode != "1"
    return nil if nv < 256 || nc < 1000
    lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
    i = 0; repeats = 0; previous = 0
    while i < 64
      return nil if lens[i] != 2
      o = offs[i]; a = lits[o]; b = lits[o + 1]
      return nil if !((a < 0 && b > 0) || (b < 0 && a > 0))
      head = a > 0 ? a : b
      repeats += 1 if head == previous; previous = head; i += 1
    return nil if repeats < 32
  # Same six-GiB resident envelope as the bounded byte worker. Account for all
  # retained scouts and existing arms; never remove a solver to admit this lane.
  scratch = 268435456 + 64 * (nv + 1) + 8 * nc
  estimate = wassat_cdcl_arena_bytes(formula) * cdcl
  estimate += wassat_sls_arena_bytes(formula) * sls
  estimate += wassat_preprocess_arena_bytes(formula) * pre + extra + scratch
  memory = System.physical_memory_bytes ## i64
  ceiling = memory / 3; ceiling = 6442450944 if ceiling > 6442450944
  wassat_prof_note("race.resource_plan estimate=[estimate] ceiling=[ceiling] scratch=[scratch]")
  return nil if memory <= 0 || estimate > ceiling
  {"resource_capacity": true, "meta": i64[64], "scratch": scratch}

-> wassat_resource_arm(formula, m, stop, res, base, nv)
  started = clock_ms(); res[base + nv + 6] = started
  r = wassat_resource_refute(formula, m, stop, started + 1000)
  res[base + nv + 5] = clock_ms(); m[38] = r; m[39] = res[base + nv + 5] - started
  if r == -1 && !wassat_stop_requested?(stop)
    z = ccall("__w_arr_store_rel", res, base, -1)
    z = wassat_stop_publish(stop, -1)
  0

-> wassat_resource_profile(m)
  wassat_prof_note("race.resource result=[m[38]] ms=[m[39]] groups=[m[0]] slots=[m[1]] choices=[m[3]] terms=[m[4]] domains=[m[5]] resources=[m[6]] witness_courses=[m[7]] demand=[m[8]] capacity=[m[9]] witness_resources=[m[10]] checked_pairs=[m[14]] implication_work=[m[15]] pair_visits=[m[18]] stop=[m[11]]")
