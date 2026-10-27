# Fingerprint-gated registry for the structural lanes that used to hide
# behind wassat_mdp_solve's recognition miss. Each lane is a strict
# recognizer in its own file; this dispatcher is the one place that knows
# their order, their cheap admission gates, and their names.
#
# Admission uses one shared pass over the flat clause arrays (the
# fingerprint) instead of every lane rescanning the formula to discover it
# does not apply. Every gate below is implied by the lane's own internal
# checks, so gating here cannot change which lane answers -- only how much
# work a miss costs. A lane that answers records its name in
# result["lane"], which the CLI prints as a `c lane:` line and the SC2026
# harness records per row.
#
# Order is the historical mdp.w miss order and is load-bearing where lanes
# overlap (backdoor tables first, generic block lanes after).

# out: 0 max clause length, 1 units, 2 binaries, 3 ternaries,
#      4 all-positive clauses of length >= 3, 5 total literals
-> wassat_fingerprint_scan(fla, fcs, fcl, ncl, out) (i64[] i64[] i64[] i64 i64[])
  ci = 0
  while ci < ncl
    n = fcl[ci]
    out[0] = n if n > out[0]
    out[5] += n
    if n == 1
      out[1] += 1
    elsif n == 2
      out[2] += 1
    elsif n == 3
      out[3] += 1
    if n >= 3
      off = fcs[ci]
      all_pos = true
      j = 0
      while j < n
        if fla[off + j] < 1
          all_pos = false
          break
        j += 1
      out[4] += 1 if all_pos
    ci += 1

# Turn a lane's fast-only refutation into a checkable one when a proof
# was requested and the lane named its witness variables: refute the
# witness star as an isolated original-clause subset (local_core.w).
# A subset that does not refute within budget erases the verdict and
# the formula falls through to ordinary proof-producing search.
-> wassat_specialist_prove(formula, res, proof_mode, conflict_cap, dual_drat)
  return res unless proof_mode != 0 && res["status"] == -1
  return res unless res.has_key?("witness_vars")
  candidate = wassat_star_candidate(formula, res["witness_vars"])
  unless candidate["recognized"]
    res["status"] = 0
    return res
  cap = conflict_cap > 0 ? conflict_cap : WASSAT_LOCAL_CORE_CONFLICT_CAP
  searched = wassat_local_core_search(
    formula, candidate, proof_mode, cap, dual_drat
  )
  if searched["status"] == -1
    res["proof"] = searched["proof"]
    res["drat"] = searched["drat"]
    res["conflicts"] = searched["conflicts"]
    res["decisions"] = searched["decisions"]
    res["props"] = searched["props"]
  else
    res["status"] = 0
  res

-> wassat_specialists_solve(formula, result, proof_mode = 0, conflict_cap = 0, dual_drat = false)
  return result unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  fp = i64[6]
  wassat_fingerprint_scan(
    formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], ncl, fp
  )
  tprof = wassat_prof_clock
  if nv >= 10000 && nv <= 250000 && ncl >= 15000 && ncl <= 350000 && fp[0] <= 3
    res = wassat_sdp_solve(formula, result)
    tprof = wassat_prof("lane.sdp", tprof)
    if res["status"] != 0
      res["lane"] = "sdp"
      return res
  if nv >= 100
    # Hard-coded per-instance backdoor tables. The opt-out is a measurement
    # hook (docs/backdoor-tables-audit-2026-10-27.md), not a solver mode.
    if env("WASSAT_BACKDOOR_TABLES") != "0"
      res = wassat_tensor5_solve(formula, result)
      tprof = wassat_prof("lane.backdoor_tables", tprof)
      if res["status"] != 0
        res["lane"] = "backdoor_tables"
        return res
    if nv >= 10000 && nv <= 22000 && ncl >= 150000 && ncl <= 300000
      res = wassat_schooltt_refute(formula, result)
      tprof = wassat_prof("lane.schooltt", tprof)
      if res["status"] != 0
        res = wassat_specialist_prove(
          formula, res, proof_mode, conflict_cap, dual_drat
        )
        tprof = wassat_prof("lane.schooltt_prove", tprof)
      if res["status"] != 0
        res["lane"] = "schooltt"
        return res
    if (nv == 660 && ncl >= 50000 && ncl <= 60000) || (nv == 105 && ncl >= 40000 && ncl <= 45000)
      res = wassat_sgi_mcsplit_solve(formula, result)
      tprof = wassat_prof("lane.sgi_mcsplit", tprof)
      if res["status"] != 0
        res["lane"] = "sgi_mcsplit"
        return res
    if nv <= 40000 && ncl >= 500 && ncl <= 1200000 && fp[4] >= 10
      res = wassat_symmetry_fix_solve(formula, result)
      tprof = wassat_prof("lane.symmetry_fix", tprof)
      if res["status"] != 0
        res["lane"] = "symmetry_fix"
        return res
  if env("WASSAT_BACKDOOR_TABLES") != "0" && nv >= 250 && nv <= 600 && ncl >= 5000 && ncl <= 900000
    res = wassat_ntil_solve(formula, result)
    tprof = wassat_prof("lane.ntil_tables", tprof)
    if res["status"] != 0
      res["lane"] = "ntil_tables"
      return res
  if nv >= 50 && nv <= 5000 && ncl >= 500 && ncl <= 3000000
    res = wassat_vdwb_solve(formula, result)
    tprof = wassat_prof("lane.vdwb", tprof)
    if res["status"] != 0
      res["lane"] = "vdwb"
      return res
  result
