# Recover necessary affine-plane constraints from the current formula.
# Every word-domain restriction and pair exclusion is checked against original
# clauses; Bruck-Ryser arithmetic can then refute an impossible plane order.
# This bounded parallel worker returns UNSAT or UNKNOWN and emits no DRAT.
use affine_design/verify

# Metrics: 0 stop, 1 polls, 2 deadline, 3 structural work, 4 wide groups,
# 5 comparisons, 6 words, 7 coordinates, 8 free rounds, 9 players,
# 10 domain clauses, 11 excluded codes, 12 defining clauses, 13 fixed pairs,
# 14 cross-round exclusions, 15 implication visits, 16/17 decode/verify ms,
# 18 verdict, 19 total ms, 20 hash probes, 21 units, 22 binary edges,
# 23 complete necessary design, 24 prime obstruction, 25 cube patterns,
# 26 signature visits, 27 triangle visits, 28 fixed-pair events, 29 arm ms.
# Fixed arrays and stamped implication queues are reused without growth.
-> wassat_affine_design_plan(formula, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_AFFINE_DESIGN")
  return nil if mode == "0" || System.cpu_count <= workers || wassat_race_round1_conflicts != 0
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return nil if nv < 1 || nv > 100000 || nc < 1 || nc > 500000 || nl < 1 || nl > 2000000
  # Only constant-size admission work precedes the race. Semantic recognition
  # and allocations run in the optional worker alongside all existing arms.
  if mode != "1"
    return nil if nv < 256 || nc < 1000
    lens = formula["flat_lens"]; return nil if lens.size < nc
    seven = 0; i = 0
    while i < 256
      seven += 1 if lens[i * nc / 256] == 7; i += 1
    return nil if seven < 32
  scratch = 67108864 + 128 * (nv + 1) + 16 * nc
  return nil unless wassat_race_memory_fits?(formula, cdcl, sls, pre, extra + scratch)
  {"affine_design": true, "meta": i64[64], "scratch": scratch}

-> wassat_affine_design_arm(formula, m, stop, res, base, nv)
  started = clock_ms(); res[base + nv + 6] = started
  r = wassat_affine_design_refute(formula, m, stop, started + 1000)
  res[base + nv + 5] = clock_ms(); m[29] = res[base + nv + 5] - started
  if r == -1 && !wassat_stop_requested?(stop)
    z = ccall("__w_arr_store_rel", res, base, -1)
    z = wassat_stop_publish(stop, -1)
  0

-> wassat_affine_design_profile(m)
  wassat_prof_note("race.affine_design result=[m[18]] ms=[m[29]] words=[m[6]] rounds=[m[8]] players=[m[9]] comparisons=[m[5]] domain_clauses=[m[10]] excluded_codes=[m[11]] defining_clauses=[m[12]] fixed_pairs=[m[13]] checked_pairs=[m[14]] fixed_events=[m[28]] implication_visits=[m[15]] structural_work=[m[3]] hash_probes=[m[20]] signature_visits=[m[26]] triangle_visits=[m[27]] geometry=[m[23]] prime=[m[24]] decode_ms=[m[16]] verify_ms=[m[17]] stop=[m[0]] polls=[m[1]]")
