# A decoded transition-system refuter. This path is not a DRAT producer and
# must only be admitted by the fast-mode portfolio after clause verification.
use atomic_stop
use naked_sudoku/kernels
use naked_sudoku/index
use naked_sudoku/checker
use naked_sudoku/search

# This entry does not publish. The portfolio owns result publication after
# stop checks and disables this non-DRAT certificate path in proof mode.
-> wassat_naked_refute(formula, meta, stop, deadline = 0, node_cap = 1000000)
  return 0 if meta.size < 64 || stop.size < 2
  i = 0
  while i < 64
    meta[i] = 0; i += 1
  start = clock_ms()
  checker = WassatNakedSudoku.new(formula, stop, deadline, meta)
  result = 0
  result = checker.search(node_cap) if checker.check
  meta[31] = clock_ms() - start
  meta[32] = result
  result

# Admission only reads the first eight order-chain clauses. Recognition,
# allocation and proof work run on the worker, alongside ordinary search.
-> wassat_naked_prefix(lits, offs, lens, nc, nl) (i64[] i64[] i64[] i64 i64) bool
  return false if nc < 8 || offs.size < nc || lens.size < nc || lits.size < nl
  ci = 0
  while ci < 8
    return false if lens[ci] != 2
    o = offs[ci]
    return false if o < 0 || o > nl - 2
    a = lits[o]; b = lits[o + 1]
    if a > b
      t = a; a = b; b = t
    return false unless a < 0 && b == 1 - a
    if a != -ci - 1
      return (ci == 2 || ci == 7) && a == -ci - 2
    ci += 1
  false

-> wassat_naked_plan(formula, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_NAKED_SUDOKU")
  return nil if mode == "0" || formula == nil || formula["naked_sudoku_done"] == true
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  return nil if System.cpu_count <= workers || System.physical_memory_bytes <= 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return nil if nv == nil || nc == nil || nl == nil
  return nil if nv < 1 || nv > 1000000 || nc < 8 || nc > 3000000 || nl < 16 || nl > 12000000
  return nil if formula["flat_lits"] == nil || formula["flat_offs"] == nil || formula["flat_lens"] == nil
  return nil unless wassat_naked_prefix(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nc, nl)
  # Includes the result slice and all fixed index/search arrays. There is no
  # per-node allocation or array growth during the semantic search.
  bytes = 1048576 + 72 * (nv + 1) + 16 * nc + 12 * nl + 8 * (nv + 8)
  return nil if bytes > System.physical_memory_bytes / 32
  # This adds fixed, bounded scratch, not a growing local-search arena.
  # Use the same resident ceiling as the existing bounded roster/resource
  # workers; retain and charge every already-admitted solver and worker.
  estimate = wassat_cdcl_arena_bytes(formula) * cdcl
  estimate += wassat_sls_arena_bytes(formula) * sls
  estimate += wassat_preprocess_arena_bytes(formula) * pre + extra + bytes
  memory = System.physical_memory_bytes ## i64
  ceiling = memory / 3; ceiling = 6442450944 if ceiling > 6442450944
  wassat_prof_note("race.naked_sudoku_plan estimate=[estimate] ceiling=[ceiling] scratch=[bytes] existing_workers=[workers]")
  return nil if estimate > ceiling
  { "meta": i64[64], "scratch": bytes }

-> wassat_naked_arm(formula, plan, stop, res, base)
  nv = formula["nvars"]; m = plan["meta"]; start = clock_ms()
  hit = wassat_naked_refute(formula, m, stop, start + 10000)
  m[33] = start; m[34] = clock_ms()
  res[base + nv + 6] = start; res[base + nv + 5] = m[34]
  hit = 0 if wassat_stop_load(stop) != 0 || m[34] >= start + 10000
  if hit == -1
    z = ccall("__w_arr_store_rel", res, base, hit)
    z = wassat_stop_publish(stop, hit)
  hit

-> wassat_naked_start(formula, plan, stop, res, base)
  Thread.new -> wassat_naked_arm(formula, plan, stop, res, base)

-> wassat_naked_finish_scout(formula, plan)
  # Retry only an interrupted attempt. A complete miss, work cap or deadline
  # is deterministic enough to avoid paying for the same attempt twice.
  # A certificate can finish just before the coordinator cancels, then be
  # withheld by the publication stop check. It is not a completed miss.
  formula["naked_sudoku_done"] = plan["meta"][0] != 1 && plan["meta"][32] != -1
  0

-> wassat_naked_profile(plan, status, label = "race.naked_sudoku")
  m = plan["meta"]
  wassat_prof_note("[label] status=[status] rank=[m[10]] stages=[m[11]] clues=[m[12]] phase=[m[16]] placement_stage=[m[13]] candidate_stage=[m[14]] progress_stages=[m[15]] queries=[m[8]] clause_queries=[m[4]] hash_probes=[m[5]] literal_compares=[m[6]] binary_visits=[m[7]] cover_visits=[m[9]] clauses=[m[2]] literals=[m[3]] work=[m[17]] polls=[m[1]] stop=[m[0]] nodes=[m[18]] branches=[m[19]] propagated=[m[20]] contradictions=[m[22]] completions=[m[23]] progress_checks=[m[25]] prunes=[m[26]] max_nonclues=[m[27]] normalized=[m[28]] first=[m[29]] scratch_bytes=[m[30]] reserved_bytes=[plan["scratch"]] ms=[m[31]]")
