# Bounded extra portfolio worker. Positive relaxed leaves never publish SAT.
use selector_latin_symmetry

WASSAT_SELECTOR_LATIN_BYTES = 67108864

-> wassat_selector_latin_run(lits, offs, lens, nv, nc, m, stop, deadline, node_cap) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < 64
    m[i] = 0
    i += 1
  m[9] = deadline
  m[10] = node_cap
  m[11] = 3
  return 0 if wassat_qg_poll(m, stop) != 0
  return 0 if nv < 49 || nv > 10000 || nc < 100 || nc > 100000 || lits.size > 1048576
  state = i64[2176 * 8]
  tables = i64[140]
  tuples = i64[14 * 4164 * 7]
  supports = i64[14 * 7 * 7 * 66]
  eoffs = i64[16384]
  elens = i64[16384]
  elits = i64[131072]
  leaves = i64[768]
  groups = i64[12]
  canonical = i64[nv + 1]
  ok = wassat_qg_decode_native(lits, offs, lens, nv, nc, state, tables, tuples, supports, eoffs, elens, elits, leaves, groups, canonical, m, stop) ## i64
  return 0 if ok == 0 || wassat_qg_poll(m, stop) != 0
  m[48] = wassat_qg_symmetry(state, tables, tuples, eoffs, elens, elits, leaves, groups, m, stop)
  return 0 if wassat_qg_poll(m, stop) != 0
  started = clock_ms() ## i64
  result = wassat_qg_dfs(0, state, tables, tuples, supports, eoffs, elens, elits, leaves, groups, i64[98], m, stop) ## i64
  m[35] = clock_ms() - started
  m[41] = result
  return 0 if wassat_qg_poll(m, stop) != 0
  result == -1 ? 1 : 0

# Last admission: preserve all established workers and memory reservations.
# Only a bounded prefix is inspected here; recognition stays in the worker.
-> wassat_selector_latin_plan(formula, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_SELECTOR_LATIN")
  return nil if mode == "0" || System.cpu_count <= workers || System.physical_memory_bytes <= 0
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 49 || nv > 10000 || nc < 100 || nc > 100000
  lits = formula["flat_lits"]
  lens = formula["flat_lens"]
  return nil if lits.size > 1048576 || lens.size < nc
  small = 0
  wide = 0
  i = 0
  while i < 64 && i < nc
    small += 1 if lens[i] <= 3
    wide += 1 if lens[i] >= 6 && lens[i] <= 32
    i += 1
  return nil if small == 0 || wide == 0
  return nil unless wassat_race_memory_fits?(formula, cdcl, sls, pre, extra + WASSAT_SELECTOR_LATIN_BYTES)
  { "selector_latin": true, "meta": i64[64] }

-> wassat_selector_latin_arm(lits, offs, lens, m, stop, res, base, nv, nc) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  started = clock_ms()
  res[base + nv + 6] = started
  hit = wassat_selector_latin_run(lits, offs, lens, nv, nc, m, stop, started + 30000, 2000000)
  res[base + nv + 5] = clock_ms()
  m[50] = res[base + nv + 5] - started
  if hit == 1 && wassat_qg_poll(m, stop) == 0
    z = ccall("__w_arr_store_rel", res, base, -1)
    won = wassat_stop_publish(stop, -1)
  hit

-> wassat_selector_latin_profile(m)
  wassat_prof_note("race.selector_latin stage=[m[40]] cells=[m[23]] lines=[m[24]] symbols=[m[25]] components=[m[30]] tuples=[m[33]] units=[m[20]] nodes=[m[0]] words=[m[1]] literals=[m[2]] leaves=[m[3]] table_fails=[m[4]] clause_fails=[m[5]] dnf_fails=[m[6]] scope_cache_hits=[m[7]] max_depth=[m[12]] polls=[m[15]] stopped=[m[8]] projection_nodes=[m[26]] projection_clauses=[m[42]] decode_literals=[m[31]] permutations=[m[32]] result=[m[41]] decode_ms=[m[34]] search_ms=[m[35]] symmetry=[m[48]] symmetry_stage=[m[44]] symmetry_ms=[m[43]] root_tuples=[m[45]] root_orbits=[m[46]] normalized_terms=[m[47]] tuple_images=[m[49]] worker_ms=[m[50]]")
