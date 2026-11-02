# A model-only companion to the light preprocessed CDCL arm. Equivalence
# substitution can turn a one-bit SLS move into a coordinated move over many
# original variables: e.g. selecting an argument also clears its attacked
# flag. Reuse the completed rendering; never delay the raw arms or replace a
# CDCL configuration. The parent owns the result slot and joins this worker
# before copying its private payload.
use atomic_stop

WASSAT_PRE_SLS_FLIPS = 2000000

-> wassat_pre_sls_shape?(formula)
  formula["nvars"] >= 64 && formula["nvars"] <= 200000 && formula["flat_ncl"] <= 500000 && formula["flat_nlits"] <= 4000000

-> wassat_pre_sls_projected?(nv, substituted, status) (i64 i64 i64) bool
  status == 0 && substituted >= 64 && substituted * 4 >= nv

# The light pipeline introduces no resolvents. Reserve room for its original
# clauses plus units, two compact clause-index arrays, the private model,
# reconstruction and validation, in addition to a full original-size SLS
# arena (conservative even when substitution deletes most clauses).
-> wassat_pre_sls_extra_bytes(formula)
  1048576 + 16 * (formula["flat_ncl"] + formula["nvars"]) + 64 * formula["nvars"]

# Keep only live, non-tautological clauses, including empty clauses. Borrow
# the now immutable literal arena; WassatSls makes its own normalized copy.
# Returning -1 on cancellation forbids treating a partial view as a formula.
-> wassat_pre_sls_view(offs, lens, alive, taut, ncl, dst_offs, dst_lens, meta, stop) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  return -1 if ncl < 0 || ncl > offs.size || ncl > lens.size
  return -1 if ncl > alive.size || ncl > taut.size || ncl > dst_offs.size || ncl > dst_lens.size
  ci = 0
  live = 0
  lits = 0
  while ci < ncl
    return -1 if (ci & 255) == 0 && wassat_stop_load(stop) != 0
    if alive[ci] == 1 && taut[ci] == 0
      dst_offs[live] = offs[ci]
      dst_lens[live] = lens[ci]
      lits += lens[ci]
      live += 1
    ci += 1
  meta[2] = live
  meta[3] = lits
  live

# meta: attempted, substituted, live clauses/literals, flips, best unsat,
# verified, start/end ms, cancelled, preparation ms, estimated extra bytes.
-> wassat_pre_sls_body(formula, art, stop, result, meta)
  meta[0] = 1
  meta[7] = clock_ms()
  meta[1] = art["stats"]["vars_substituted"]
  if wassat_stop_requested?(stop)
    meta[9] = 1
    meta[8] = clock_ms()
    return 0
  nv = formula["nvars"]
  ncl = art["fncl"]
  offs = i64[ncl]
  lens = i64[ncl]
  live = wassat_pre_sls_view(art["fcs"], art["fcl"], art["falive"],
    art["ftaut"], ncl, offs, lens, meta, stop)
  if live >= 0 && !wassat_stop_requested?(stop)
    view = { "flat_ncl": live, "flat_lits": art["fla"],
             "flat_offs": offs, "flat_lens": lens }
    s = WassatSls.new(nv, [], stop, view)
    s.set_stop_cell(stop)
    meta[10] = clock_ms() - meta[7]
    r = s.solve(WASSAT_PRE_SLS_FLIPS, 1)
    meta[4] = r["flips"]
    meta[5] = r["best_unsat"]
    if r["sat"] && !wassat_stop_requested?(stop)
      model = wassat_reconstruct_model(art["stack"], r["model"], nv)
      # The reduced model is only a proposal. Check every original clause
      # before cancelling decisive work, and leave a failed replay a miss.
      if wassat_model_satisfies?(formula, model) && !wassat_stop_requested?(stop)
        reduced = r["model"]
        v = 1
        while v <= nv
          result[v] = reduced[v - 1] > 0 ? 1 : 0
          v += 1
        meta[6] = 1
        meta[8] = clock_ms()
        result[0] = 1
        won = wassat_stop_publish(stop, 1)
        return 0
  meta[9] = wassat_stop_requested?(stop) ? 1 : 0
  meta[8] = clock_ms()
  0

-> wassat_pre_sls_copy(result, res, base, nv) (i64[] i64[] i64 i64)
  v = 1
  while v <= nv
    res[base + v] = result[v]
    v += 1
  res[base] = 1

-> wassat_pre_sls_profile(meta, joined)
  wassat_prof_note("race.pre_sls substituted=[meta[1]] clauses=[meta[2]] literals=[meta[3]] flips=[meta[4]] best_unsat=[meta[5]] verified=[meta[6]] cancelled=[meta[9]] prepare_ms=[meta[10]] ms=[meta[8] - meta[7]] finish_to_join_ms=[joined - meta[8]] extra_bytes=[meta[11]]")
