# Bounded original-clause local-core scouting.
#
# Large generated formulas are often laid out by construction: a compact
# prefix defines one transition or time step, while later clause blocks tie
# its interface variables to local auxiliaries and domain constraints.  If
# that exact original-clause subset is already UNSAT, searching the remaining
# million clauses is wasted work.
#
# This pass deliberately knows nothing about a benchmark name, variable
# interval, or encoding semantics.  It takes a bounded prefix as a seed and
# selects its one-hop incidence star: every original clause touching any seed
# variable.  The scout is refute-only.  A SAT/UNKNOWN subset falls through; an
# UNSAT result is a proof of the full formula because every selected clause is
# literally one of its axioms.
#
# WRAT/LRAT input ids remain the original one-based DIMACS clause ids.  Fresh
# search clauses start after the FULL input clause count, not after the subset,
# so omitted clauses can never collide with learned proof ids.  Plain DRAT is
# safe for Wassat's search too: every emitted addition is RUP, and RUP remains
# valid when omitted original clauses are restored.

use solver

WASSAT_LOCAL_CORE_MIN_NVARS = 100000
WASSAT_LOCAL_CORE_MIN_CLAUSES = 500000
WASSAT_LOCAL_CORE_MIN_LITERALS = 2000000
WASSAT_LOCAL_CORE_MAX_NVARS = 1000000
WASSAT_LOCAL_CORE_MAX_CLAUSES = 5000000
WASSAT_LOCAL_CORE_MAX_LITERALS = 20000000
WASSAT_LOCAL_CORE_PREFIX_CLAUSES = 16384
WASSAT_LOCAL_CORE_CLAUSE_CAP = 32768
WASSAT_LOCAL_CORE_LITERAL_CAP = 1000000
WASSAT_LOCAL_CORE_CONFLICT_CAP = 300000

-> wassat_local_core_miss
  { "recognized": false, "status": 0, "conflicts": 0,
    "clauses": 0, "variables": 0, "prefix": 0,
    "proof": [], "drat": [] }

# Return 1 and fill `picked` / `marks` for a bounded candidate, else 0.
#
# seed: 0 outside, 1 prefix variable. used marks every variable in the star.
# pm: [0] seed vars [1] star vars [2] selected clauses [3] selected literals.
-> wassat_local_core_select(fla, fcs, fcl, seed, used, picked, pm,
                            nv, ncl, prefix, out_cap) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  return 0 if prefix <= 0 || prefix >= ncl || out_cap < prefix

  seed_vars = 0
  ci = 0
  while ci < prefix
    n = fcl[ci]
    # The scout exists for compact generated encodings. A wide prefix is both
    # a poor local boundary and a potentially expensive miss.
    return 0 if n > 8
    st = fcs[ci]
    j = 0
    while j < n
      l = fla[st + j]
      v = l < 0 ? 0 - l : l
      return 0 if v <= 0 || v > nv
      if seed[v] == 0
        seed[v] = 1
        seed_vars += 1
        # Five of 178 local competition rows pass the prefix checks; the
        # incidence caps below reject four of them before a solver is built.
        return 0 if seed_vars > 8192
      j += 1
    ci += 1
  return 0 if seed_vars == 0

  # One incidence hop over the ORIGINAL clauses. Stop as soon as either the
  # clause star or its variable boundary ceases to be local; the four broad
  # prefix matches outside SPG hit one of these caps.
  count = 0
  selected_lits = 0
  used_vars = 0
  ci = 0
  while ci < ncl
    st = fcs[ci]
    n = fcl[ci]
    touches = 0
    j = 0
    while j < n && touches == 0
      l = fla[st + j]
      v = l < 0 ? 0 - l : l
      touches = 1 if seed[v] == 1
      j += 1
    if touches == 1
      return 0 if count >= out_cap
      return 0 if selected_lits + n > WASSAT_LOCAL_CORE_LITERAL_CAP
      picked[count] = ci
      count += 1
      selected_lits += n
      j = 0
      while j < n
        l = fla[st + j]
        v = l < 0 ? 0 - l : l
        if used[v] == 0
          used[v] = 1
          used_vars += 1
          return 0 if used_vars > 2 * seed_vars
        j += 1
    ci += 1

  # A useful core is substantially more local than its parent and contains
  # real boundary support beyond the seed prefix.
  return 0 if count < prefix + 1000
  return 0 if ncl < count * 32

  pm[0] = seed_vars
  pm[1] = used_vars
  pm[2] = count
  pm[3] = selected_lits
  1

-> wassat_local_core_candidate(formula)
  miss = wassat_local_core_miss
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  nlits = formula["flat_nlits"]
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  return miss if nv < WASSAT_LOCAL_CORE_MIN_NVARS
  return miss if ncl < WASSAT_LOCAL_CORE_MIN_CLAUSES
  return miss if nlits < WASSAT_LOCAL_CORE_MIN_LITERALS
  # The recognized solver intentionally retains original variable numbers for
  # proof replay. Bound both its dense state and the speculative incidence
  # scan; larger candidates need true variable remapping rather than silently
  # gambling hundreds of MiB on an unmeasured scout.
  return miss if nv > WASSAT_LOCAL_CORE_MAX_NVARS
  return miss if ncl > WASSAT_LOCAL_CORE_MAX_CLAUSES
  return miss if nlits > WASSAT_LOCAL_CORE_MAX_LITERALS

  prefix = WASSAT_LOCAL_CORE_PREFIX_CLAUSES
  return miss if ncl <= prefix
  seed = i64[nv + 1]
  used = i64[nv + 1]
  picked = i64[WASSAT_LOCAL_CORE_CLAUSE_CAP]
  pm = i64[8]
  ok = wassat_local_core_select(
    lits, offs, lens,
    seed, used, picked, pm, nv, ncl, prefix, WASSAT_LOCAL_CORE_CLAUSE_CAP
  )
  return miss if ok == 0

  # Materialize only the selected flat slices. The full formula deliberately
  # stays unboxed: doing 1.5M Array allocations to obtain a 25k-clause core
  # would erase the win before search began.
  clauses = []
  gids = []
  k = 0
  while k < pm[2]
    ci = picked[k]
    st = offs[ci]
    n = lens[ci]
    clause = []
    j = 0
    while j < n
      clause.push(lits[st + j])
      j += 1
    clauses.push(clause)
    gids.push(ci + 1)
    k += 1

  { "recognized": true, "clauses": clauses, "gids": gids,
    "used": used, "prefix": prefix, "seed_variables": pm[0],
    "variables": pm[1], "literals": pm[3],
    "status": 0, "conflicts": 0, "proof": [], "drat": [] }

# Search an already selected candidate as an isolated, refute-only formula.
# This split keeps the proof-lifting boundary directly testable on tiny,
# non-contiguous original-clause subsets without manufacturing a competition-
# scale instance merely to pass the conservative recognition gate.
-> wassat_local_core_search(formula, candidate, proof_mode, max_conflicts, dual_drat)
  solver = Wassat.new(formula["nvars"], candidate["clauses"], proof_mode, 0)
  # The SPG-family core this structural scout isolates is a repeatable OTFS
  # win. Keep the side-lemma trajectory local to this proof-safe subset; the
  # generic race carries its own diversified specialist instead.
  solver.enable_otfs
  solver.seed_proof_ids(candidate["gids"], formula["flat_ncl"] + 1)
  solver.retire_absent_variables(candidate["used"])
  solver.enable_dual_drat if dual_drat
  result = solver.solve_budget(max_conflicts)
  candidate["status"] = result["status"]
  candidate["conflicts"] = result["conflicts"]
  candidate["decisions"] = result["decisions"]
  candidate["props"] = result["props"]
  candidate["model"] = result["model"] if result["status"] == 1
  if result["status"] == -1
    candidate["proof"] = result["proof"]
    candidate["drat"] = result["drat"]
  candidate

# Search the candidate as an isolated, refute-only formula. No clause sharing:
# imported clauses from a full-formula arm need not follow from this subset.
-> wassat_local_core_refute(formula, proof_mode, max_conflicts, dual_drat)
  candidate = wassat_local_core_candidate(formula)
  return candidate unless candidate["recognized"]
  wassat_local_core_search(formula, candidate, proof_mode, max_conflicts, dual_drat)
