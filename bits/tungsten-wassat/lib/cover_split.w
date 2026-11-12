# Parallel case split for dense conflict-constrained covering formulas.
#
# The shape is covering.w's: positive rows of width three and up, each needing
# one selected variable, and negative binary clauses forbidding pairs. When
# the conflict graph is dense and every variable sits in many rows (SCPC-500-*:
# 500 variables, 3,000 rows, ~12,500 conflicts, ~120 rows per variable)
# covering.w's row DFS declines and the formula goes to the CDCL race. The race is a portfolio, and a portfolio buys nothing on a refutation:
# every arm needs roughly the same few hundred thousand conflicts, so eight
# arms do eight times the work of one for the same wall time.
#
# A positive row (v1 .. vk) is an exact case list. Case i asserts v_i and
# denies v_1 .. v_{i-1}; the row is a clause of the input, so every model of
# the input lies in exactly one case. Each case is a much smaller problem --
# one selection covers every row it sits in and removes its conflict
# neighbours -- and the cases are independent, so they are refuted in
# parallel. Measured with CaDiCaL 3.0.1 on SCPC-500-19: 566k conflicts whole,
# against seven cases of 40k-91k conflicts (469k in total).
#
# Soundness. A case formula is the input's own clauses plus unit clauses,
# nothing else. Its solver is an ordinary Wassat over that formula, so:
#   * a model of any case satisfies the input; it is still replayed against
#     the input by the caller before it is printed;
#   * UNSAT is concluded only when EVERY case of the list reports a completed
#     refutation. A case that was stopped, never claimed, or retired makes the
#     lane report UNKNOWN and the ordinary pipeline runs.
# Completeness of the list is syntactic. Cases are only ever refined by
# splitting on a second input row of which the case already denies some
# literals (its own negative units): the row must still be satisfied, the
# denied literals cannot do it, so one of the remaining ones does. No learned
# clause crosses between cases and no case reasons about another.
#
# Fast mode only: a refutation by cases has no single DRAT stream here.
use atomic_stop

WASSAT_COVER_SPLIT_MIN_VARS = 350
WASSAT_COVER_SPLIT_MAX_VARS = 2048
# Covering proper: every variable sits in at least this many rows on average.
# The same clause shape also renders one-row-per-variable CSPs (frb, rbsat,
# round-robin, colouring: 0.5-3 row occurrences per variable). Those are
# model searches the race and the earlier lanes already own, and a case list
# over one CSP domain measurably loses them: frb80-14-1 and rbsat-v1375 both
# ran out the 60s budget inside the lane before this floor existed.
WASSAT_COVER_SPLIT_MIN_ROW_DENSITY = 8
WASSAT_COVER_SPLIT_MAX_CLAUSES = 220000
WASSAT_COVER_SPLIT_MAX_CASES = 64
WASSAT_COVER_SPLIT_MAX_WORKERS = 12

# Strict shape census over the parser's flat arrays.
# out: 0 positive rows, 1 negative binaries, 2 row literal occurrences.
# Returns 1 for the exact covering shape, 0 for anything else.
-> wassat_cover_split_census(fla, fcs, fcl, ncl, nvars, out) (i64[] i64[] i64[] i64 i64 i64[]) i64
  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    if n >= 3
      j = 0
      while j < n
        v = fla[off + j]
        return 0 if v < 1 || v > nvars
        j += 1
      out[0] += 1
      out[2] += n
    elsif n == 2
      a = fla[off]
      b = fla[off + 1]
      return 0 unless a < 0 && b < 0
      return 0 if a < 0 - nvars || b < 0 - nvars || a == b
      out[1] += 1
    else
      return 0
    ci += 1
  1

# The narrowest positive row a case leaves undecided. mark[v] is the case's
# own assignment: 1 asserted, -1 denied, 0 open. Rows containing an asserted
# variable are satisfied and skipped. Returns the clause index or -1, with
# the number of open literals in out[0].
-> wassat_cover_split_pick(fla, fcs, fcl, ncl, mark, out) (i64[] i64[] i64[] i64 i8[] i64[]) i64
  best = 0 - 1
  best_nfree = 0
  ci = 0
  while ci < ncl
    n = fcl[ci]
    if n >= 3
      off = fcs[ci]
      nfree = 0
      sat = 0
      j = 0
      while j < n
        m = mark[fla[off + j]]
        sat = 1 if m > 0
        nfree += 1 if m == 0
        j += 1
      if sat == 0 && (best < 0 || nfree < best_nfree)
        best = ci
        best_nfree = nfree
    ci += 1
  out[0] = best_nfree
  best

# Worker threads this lane may start beside the coordinator.
-> wassat_cover_split_workers
  if env("WASSAT_COVER_SPLIT_WORKERS") != nil
    return wassat_decimal_in_range("WASSAT_COVER_SPLIT_WORKERS", env("WASSAT_COVER_SPLIT_WORKERS"), 1, 64)
  workers = System.cpu_count - 2
  workers = WASSAT_COVER_SPLIT_MAX_WORKERS if workers > WASSAT_COVER_SPLIT_MAX_WORKERS
  workers

# Requested length of the case list, before the memory envelope trims it.
-> wassat_cover_split_case_limit
  if env("WASSAT_COVER_SPLIT_CASES") != nil
    return wassat_decimal_in_range("WASSAT_COVER_SPLIT_CASES", env("WASSAT_COVER_SPLIT_CASES"), 1, 256)
  WASSAT_COVER_SPLIT_MAX_CASES

# Admission. `forced` drops the size and density floors so small generated
# formulas reach the lane in tests (WASSAT_COVER_SPLIT_FORCE=1 from the CLI);
# the strict shape, the resource ceilings and the worker requirement stay.
-> wassat_cover_split_admit(formula, forced, workers)
  return nil unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return nil if nv < 1 || nv > WASSAT_COVER_SPLIT_MAX_VARS
  return nil if ncl < 2 || ncl > WASSAT_COVER_SPLIT_MAX_CLAUSES
  return nil if nv < WASSAT_COVER_SPLIT_MIN_VARS && !forced
  return nil if workers < 2
  counts = i64[4]
  shape = wassat_cover_split_census(
    formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], ncl, nv, counts
  )
  return nil if shape == 0 || counts[0] == 0 || counts[1] == 0
  # The density at which covering.w stops searching rows itself.
  return nil if counts[1] < 20 * nv && !forced
  return nil if counts[2] < WASSAT_COVER_SPLIT_MIN_ROW_DENSITY * nv && !forced
  { "nv": nv, "ncl": ncl, "rows": counts[0], "edges": counts[1],
    "lits": counts[2] + 2 * counts[1] }

# Split one case on the narrowest row it leaves undecided. The case's units
# sit in units[lo...hi]; sub-cases are appended to `cases` (flat literals)
# and `ends` (one end offset per case). At most `limit` sub-cases: when the
# row has more open literals, the last sub-case only denies the earlier ones.
# Returns the number of sub-cases written, or 0 when the case is left whole
# (no undecided row, a row with fewer than two open literals, or no room).
-> wassat_cover_split_expand(formula, units, lo, hi, limit, cases, ends, mark)
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  ncl = formula["flat_ncl"]
  return 0 if limit < 2
  p = lo
  while p < hi
    lit = units[p]
    if lit > 0
      mark[lit] = 1
    else
      mark[0 - lit] = 0 - 1
    p += 1
  width = i64[1]
  row = wassat_cover_split_pick(fla, fcs, fcl, ncl, mark, width)
  written = 0
  if row >= 0 && width[0] >= 2
    avail = []
    off = fcs[row]
    n = fcl[row]
    j = 0
    while j < n
      v = fla[off + j]
      if mark[v] == 0
        avail.push(v)
        # Denied from here on, which also drops a repeated literal.
        mark[v] = 0 - 1
      j += 1
    take = avail.size
    take = limit if take > limit
    k = 0
    while k < take
      p = lo
      while p < hi
        cases.push(units[p])
        p += 1
      # The closing sub-case of a truncated list asserts nothing new.
      cases.push(avail[k]) unless k == take - 1 && avail.size > limit
      j = 0
      while j < k
        cases.push(0 - avail[j])
        j += 1
      ends.push(cases.size)
      k += 1
    written = take
    j = 0
    while j < avail.size
      mark[avail[j]] = 0
      j += 1
  p = lo
  while p < hi
    lit = units[p]
    mark[lit > 0 ? lit : 0 - lit] = 0
    p += 1
  written

# The case list: the narrowest row, then each case refined once more while
# the list stays within `cap`. Returns { "lits", "ends" } with one end offset
# per case into the flat unit list, or nil when no row yields two cases.
-> wassat_cover_split_cases(formula, cap)
  nv = formula["nvars"]
  mark = i8[nv + 1]
  top = []
  top_ends = []
  none = []
  made = wassat_cover_split_expand(formula, none, 0, 0, cap, top, top_ends, mark)
  return nil if made < 2
  lits = []
  ends = []
  pending = made
  lo = 0
  k = 0
  while k < made
    hi = top_ends[k]
    pending -= 1
    # Room for this case's refinement once every case already written and
    # every later first-level case keeps one slot.
    room = cap - ends.size - pending
    wrote = wassat_cover_split_expand(formula, top, lo, hi, room, lits, ends, mark)
    if wrote == 0
      p = lo
      while p < hi
        lits.push(top[p])
        p += 1
      ends.push(lits.size)
    lo = hi
    k += 1
  { "lits": lits, "ends": ends }

# Compact copy: the parser's offsets need not be contiguous, a loader's are.
-> wassat_cover_split_copy(fla, fcs, fcl, ncl, out_lits, out_offs, out_lens) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  pos = 0
  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    out_offs[ci] = pos
    out_lens[ci] = n
    j = 0
    while j < n
      out_lits[pos] = fla[off + j]
      pos += 1
      j += 1
    ci += 1
  pos

# The input plus one case's unit clauses, as a parser-shaped flat formula.
# `nl` is the census's exact literal count for the input.
-> wassat_cover_split_formula(formula, nl, lits, lo, hi)
  ncl = formula["flat_ncl"]
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  extra = hi - lo
  out_lits = i64[nl + extra + 1]
  out_offs = i64[ncl + extra + 1]
  out_lens = i64[ncl + extra + 1]
  pos = wassat_cover_split_copy(fla, fcs, fcl, ncl, out_lits, out_offs, out_lens)
  raise "internal error: covering census disagrees with the clause arrays" unless pos == nl
  ci = ncl
  p = lo
  while p < hi
    out_lits[pos] = lits[p]
    out_offs[ci] = pos
    out_lens[ci] = 1
    pos += 1
    ci += 1
    p += 1
  { "nvars": formula["nvars"], "flat_ncl": ncl + extra, "flat_nlits": nl + extra,
    "flat_lits": out_lits, "flat_offs": out_offs, "flat_lens": out_lens }

# One worker: claim unowned cases in list order and solve each to completion.
# Boxed arrays are only iterated here, never subscripted (see sls.w); the
# claim table and the result slab are typed. A published model stops the
# remaining claims; nothing else does.
-> wassat_cover_split_worker(solvers, claims, res, stride, stop)
  slot = 0
  solvers.each -> (solver)
    unless wassat_stop_requested?(stop)
      if ccall("__w_arr_compare_exchange", claims, slot, 0, 1) == 1
        solver.solve_case(res, slot * stride)
    slot += 1
  0

# Decide the formula by cases with explicit knobs (the CLI entry below reads
# them from policy and the measurement hooks).
#   cap      longest case list; trimmed to the race's memory envelope
#   workers  worker threads
#   walk     1 also runs the model-only local-search arm over the whole input
# status: 1 model (in "model"), -1 every case refuted, 0 not admitted or not
# completed.
-> wassat_cover_split_run(formula, forced, cap, workers, walk)
  miss = { "status": 0, "admitted": false, "model": [], "cases": 0,
           "workers": 0, "refuted": 0, "conflicts": 0, "max_conflicts": 0,
           "build_ms": 0, "search_ms": 0, "sls": 0, "retired": 0 }
  plan = wassat_cover_split_admit(formula, forced, workers)
  return miss if plan == nil
  # One resident CDCL arena per case, inside the race's own memory envelope
  # (policy.w wassat_race_memory_fits?).
  while cap > 1 && !wassat_race_memory_fits?(formula, cap, walk)
    cap -= 1
  return miss if cap < 2
  started = clock_ms()
  nv = plan["nv"]
  list = wassat_cover_split_cases(formula, cap)
  return miss if list == nil
  lits = list["lits"]
  ends = list["ends"]
  ncases = ends.size
  return miss if ncases < 2
  workers = ncases if workers > ncases

  stride = nv + 8
  stop = i64[4]
  claims = i64[ncases + 1]
  # One slab per case plus one for the model-only walker.
  res = i64[(ncases + 1) * stride]
  solvers = []
  lo = 0
  k = 0
  while k < ncases
    hi = ends[k]
    art = wassat_raw_artifact(wassat_cover_split_formula(formula, plan["lits"], lits, lo, hi), nv)
    # The configuration a lone raw arm gets (portfolio.w wassat_race_build).
    s = Wassat.from_flat(nv, art, 0)
    s.enable_fixed_caps
    s.set_stop_cell(stop)
    s.enable_chrono
    s.simplify_raw if art["config"].force_simplify?
    solvers.push(s)
    lo = hi
    k += 1

  # Local search over the WHOLE input, as in the race: a satisfiable formula
  # of this shape is its job, and its model stops the case workers.
  sls_flips = walk == 1 ? wassat_sls_arm_flips : 0
  sls_flips = 0 unless wassat_sls_arm_memory_allowed?(formula)
  sls_base = ncases * stride
  sls_handle = nil
  built = clock_ms()
  handles = []
  w = 0
  while w < workers
    handles.push(Thread.new -> wassat_cover_split_worker(solvers, claims, res, stride, stop))
    w += 1
  if sls_flips > 0
    walk_art = wassat_raw_artifact(formula, nv)
    sls_handle = Thread.new -> wassat_sls_arm_body(nv, formula, walk_art, res, sls_base, stop, sls_flips, 7)
  handles.each -> (handle)
    z = handle.join
  # Every case is finished or abandoned. A walker still searching an
  # unsatisfiable input is released by plain cancellation, which claims no
  # verdict; its own model, if it has one, was published before this point.
  if sls_handle != nil
    z = wassat_stop_cancel(stop)
    z = sls_handle.join
  finished = clock_ms()

  refuted = 0
  retired = 0
  conflicts = 0
  largest = 0
  model_base = 0 - 1
  k = 0
  while k < ncases
    base = k * stride
    status = res[base]
    refuted += 1 if status == 0 - 1
    retired += 1 if status == 2
    model_base = base if status == 1 && model_base < 0
    spent = res[base + nv + 4]
    conflicts += spent
    largest = spent if spent > largest
    k += 1
  model_base = sls_base if model_base < 0 && res[sls_base] == 1

  out = { "status": 0, "admitted": true, "model": [], "cases": ncases,
          "workers": workers, "refuted": refuted, "conflicts": conflicts,
          "max_conflicts": largest, "build_ms": built - started,
          "search_ms": finished - built, "sls": sls_flips > 0 ? 1 : 0,
          "retired": retired }
  if model_base >= 0
    model = []
    v = 1
    while v <= nv
      model.push(res[model_base + v] == 1 ? v : 0 - v)
      v += 1
    out["model"] = model
    out["status"] = 1
  elsif refuted == ncases
    out["status"] = 0 - 1
  out

# CLI entry: policy defaults, with the measurement and test hooks.
#   WASSAT_COVER_SPLIT_FORCE=1    admit small/sparse covering formulas (tests)
#   WASSAT_COVER_SPLIT_CASES=n    case-list length
#   WASSAT_COVER_SPLIT_WORKERS=n  worker threads
#   WASSAT_COVER_SPLIT_SLS=0      no local-search arm
-> wassat_cover_split_solve(formula)
  wassat_cover_split_run(
    formula, env("WASSAT_COVER_SPLIT_FORCE") == "1",
    wassat_cover_split_case_limit, wassat_cover_split_workers,
    env("WASSAT_COVER_SPLIT_SLS") == "0" ? 0 : 1
  )
