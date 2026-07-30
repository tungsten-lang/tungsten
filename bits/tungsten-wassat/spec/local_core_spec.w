use spec
use wassat
use ../../tungsten-wrat/lib/wrat

LOCAL_CORE_FULL = "p cnf 8 8\n1 0\n7 8 0\n-1 2 0\n7 -8 0\n-2 3 0\n-7 8 0\n3 0\n-7 -8 0\n"

LOCAL_CORE_ALL_FOUR = [[7, 8], [7, -8], [-7, 8], [-7, -8]]
LOCAL_CORE_ALL_FOUR_GIDS = [2, 4, 6, 8]

# A small native fixture for the generic selector. Its 1,001-clause star is
# exactly 32x smaller than the parent, matching the production locality gate
# without allocating a competition-scale formula.
-> local_core_selector_fixture
  ncl = 32032
  nlits = 1 + 1000 * 2 + (ncl - 1001)
  lits = i64[nlits]
  offs = i64[ncl]
  lens = i64[ncl]
  ci = 0
  li = 0
  while ci < ncl
    offs[ci] = li
    if ci == 0
      lens[ci] = 1
      lits[li] = 1
      li += 1
    elsif ci <= 1000
      lens[ci] = 2
      lits[li] = 1
      lits[li + 1] = 2
      li += 2
    else
      lens[ci] = 1
      lits[li] = 3
      li += 1
    ci += 1
  { "lits": lits, "offs": offs, "lens": lens, "ncl": ncl }

-> local_core_manual_candidate(clauses, gids, nvars)
  used = i64[nvars + 1]
  clauses.each -> (clause)
    clause.each -> (lit)
      v = lit < 0 ? 0 - lit : lit
      used[v] = 1
  { "recognized": true, "clauses": clauses, "gids": gids,
    "used": used, "prefix": 1, "seed_variables": 2,
    "variables": 2, "literals": 8,
    "status": 0, "conflicts": 0, "proof": [], "drat": [] }

-> local_core_seed_ids(ids, next_gid)
  solver = Wassat.new(2, [[1], [-1]], WASSAT_PROOF_WRAT, 0)
  solver.seed_proof_ids(ids, next_gid)

describe "Wassat bounded original-clause local core" ->
  context "generic candidate selection" ->
    it "selects a compact one-hop incidence star and marks every live variable" ->
      f = local_core_selector_fixture
      seed = i64[4]
      used = i64[4]
      picked = i64[2000]
      pm = i64[8]
      ok = wassat_local_core_select(
        f["lits"], f["offs"], f["lens"], seed, used, picked, pm,
        3, f["ncl"], 1, 2000
      )
      expect(ok).to eq(1)
      expect(pm[0]).to eq(1)
      expect(pm[1]).to eq(2)
      expect(pm[2]).to eq(1001)
      expect(picked[0]).to eq(0)
      expect(picked[1000]).to eq(1000)
      every_literal_marked = true
      k = 0
      while k < pm[2]
        ci = picked[k]
        j = 0
        while j < f["lens"][ci]
          lit = f["lits"][f["offs"][ci] + j]
          v = lit < 0 ? 0 - lit : lit
          every_literal_marked = false if used[v] == 0
          j += 1
        k += 1
      expect(every_literal_marked).to eq(true)

    it "rejects wide seeds, broad boundaries, clause overflow, and literal overflow" ->
      f = local_core_selector_fixture
      f["lens"][0] = 9
      expect(wassat_local_core_select(
        f["lits"], f["offs"], f["lens"], i64[4], i64[4],
        i64[2000], i64[8], 3, f["ncl"], 1, 2000
      )).to eq(0)

      lits = i64[4]
      lits[0] = 1
      lits[1] = 1
      lits[2] = 2
      lits[3] = 3
      offs = i64[2]
      offs[1] = 1
      lens = i64[2]
      lens[0] = 1
      lens[1] = 3
      expect(wassat_local_core_select(
        lits, offs, lens, i64[4], i64[4], i64[2], i64[8],
        3, 2, 1, 2
      )).to eq(0)

      lens[1] = 1
      expect(wassat_local_core_select(
        lits, offs, lens, i64[4], i64[4], i64[1], i64[8],
        3, 2, 1, 1
      )).to eq(0)

      lens[1] = WASSAT_LOCAL_CORE_LITERAL_CAP + 1
      expect(wassat_local_core_select(
        lits, offs, lens, i64[4], i64[4], i64[2], i64[8],
        3, 2, 1, 2
      )).to eq(0)

    it "misses cheaply outside the competition-scale outer gate" ->
      formula = wassat_parse_cnf_native("p cnf 3 1\n1 0\n")
      expect(wassat_local_core_candidate(formula)["recognized"]).to eq(false)

  context "proof-safe isolated search" ->
    it "lifts sparse original clause ids into independently checked WRAT and DRAT" ->
      formula = wassat_parse_cnf_native(LOCAL_CORE_FULL)
      candidate = local_core_manual_candidate(
        LOCAL_CORE_ALL_FOUR, LOCAL_CORE_ALL_FOUR_GIDS, 8
      )
      result = wassat_local_core_search(
        formula, candidate, WASSAT_PROOF_WRAT, 0, true
      )
      expect(result["status"]).to eq(-1)
      expect(result["proof"].empty?).to eq(false)
      expect(result["drat"].empty?).to eq(false)
      expect(wassat_tokenize(result["proof"][0])[0]).to eq("9")
      wrat_text = "wrat 1\n" + result["proof"].join("\n") + "\n"
      drat_text = result["drat"].join("\n") + "\n"
      expect(wrat_verify(LOCAL_CORE_FULL, wrat_text)["verified"]).to eq(true)
      expect(wrat_verify(LOCAL_CORE_FULL, drat_text)["verified"]).to eq(true)

    it "treats subset SAT and budget UNKNOWN as fallthrough-only results" ->
      formula = wassat_parse_cnf_native(LOCAL_CORE_FULL)
      sat_candidate = local_core_manual_candidate([[7, 8]], [2], 8)
      sat = wassat_local_core_search(
        formula, sat_candidate, WASSAT_PROOF_NONE, 0, false
      )
      expect(sat["status"]).to eq(1)
      expect(wassat_model_satisfies?(formula, sat["model"])).to eq(false)
      expect(sat["proof"].empty?).to eq(true)
      expect(sat["drat"].empty?).to eq(true)

      unknown_candidate = local_core_manual_candidate(
        LOCAL_CORE_ALL_FOUR, LOCAL_CORE_ALL_FOUR_GIDS, 8
      )
      unknown = wassat_local_core_search(
        formula, unknown_candidate, WASSAT_PROOF_WRAT, 1, true
      )
      expect(unknown["status"]).to eq(0)
      expect(unknown["conflicts"]).to eq(1)
      expect(unknown["proof"].empty?).to eq(true)
      expect(unknown["drat"].empty?).to eq(true)

  context "proof ids and sparse coordinates" ->
    it "accepts only complete, positive, increasing proof-id tables" ->
      expect(-> () local_core_seed_ids([1], 3)).to raise_error
      expect(-> () local_core_seed_ids([0, 2], 3)).to raise_error
      expect(-> () local_core_seed_ids([1, 1], 3)).to raise_error
      expect(-> () local_core_seed_ids([2, 1], 3)).to raise_error
      expect(-> () local_core_seed_ids([2, 4], 4)).to raise_error
      expect(local_core_seed_ids([2, 4], 5)).to eq(0)

    it "rejects unsafe bitmaps and never branches on correctly retired coordinates" ->
      too_short = Wassat.new(8, [[8]], WASSAT_PROOF_NONE, 0)
      expect(-> () too_short.retire_absent_variables(i64[8])).to raise_error

      live_missing = Wassat.new(8, [[8]], WASSAT_PROOF_NONE, 0)
      expect(-> () live_missing.retire_absent_variables(i64[9])).to raise_error

      solver = Wassat.new(4096, [[4096]], WASSAT_PROOF_NONE, 0)
      used = i64[4097]
      used[4096] = 1
      expect(solver.retire_absent_variables(used)).to eq(0)
      result = solver.solve_budget(0)
      expect(result["status"]).to eq(1)
      expect(result["decisions"]).to eq(0)

spec_summary
