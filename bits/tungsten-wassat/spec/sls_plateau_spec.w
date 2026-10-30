# Preserve plateau retirement and cancellation state across SLS pauses.
use spec
use ../lib/wassat

SLS_CONTINUATION_UNSAT = "p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n"

-> sls_continuation_flat(text)
  boxed = wassat_parse_cnf(text)
  ncl = boxed["clauses"].size
  nlits = 0
  boxed["clauses"].each -> (c)
    nlits += c.size
  fla = i64[nlits]
  fcs = i64[ncl]
  fcl = i64[ncl]
  ci = 0
  pos = 0
  boxed["clauses"].each -> (c)
    fcs[ci] = pos
    fcl[ci] = c.size
    c.each -> (l)
      fla[pos] = l
      pos += 1
    ci += 1
  { "nvars": boxed["nvars"], "clauses": boxed["clauses"],
    "flat_lits": fla, "flat_offs": fcs, "flat_lens": fcl,
    "flat_ncl": ncl, "flat_nlits": nlits }

describe "SLS plateau continuation" ->
  context "continued plateau and cancellation" ->
    it "keeps retirement windows across a pause" ->
      f = sls_continuation_flat(SLS_CONTINUATION_UNSAT)
      straight = WassatSls.new(2, [], nil, f)
      straight.set_plateau(100, 2)
      a = straight.solve(1000, 3)
      staged = WassatSls.new(2, [], nil, f)
      staged.set_plateau(100, 2)
      z = staged.solve(150, 3)
      b = staged.continue_solve(1000, 3)
      expect(b["flips"]).to eq(a["flips"])
      expect(b["retired"]).to eq(true)
      expect(b["best_assign"]).to eq(a["best_assign"])
      c = staged.continue_solve(2000, 3)
      expect(c["flips"]).to eq(b["flips"])
      d = staged.solve(50, 3)
      expect(d["retired"]).to eq(false)
      expect(d["flips"]).to eq(50)

    it "moves a stopped prefix to a new stop cell without changing its walk" ->
      f = sls_continuation_flat(SLS_CONTINUATION_UNSAT)
      straight = WassatSls.new(2, [], nil, f)
      straight.set_plateau(100, 3)
      a = straight.solve(1000, 3)
      staged = WassatSls.new(2, [], nil, f)
      staged.set_plateau(100, 3)
      old_stop = i64[4]
      staged.set_stop_cell(old_stop)
      z = staged.solve(150, 3)
      wassat_stop_cancel(old_stop)
      z = staged.continue_solve(1000, 3)
      expect(z["flips"]).to eq(150)
      staged.set_stop_cell(i64[4])
      b = staged.continue_solve(1000, 3)
      expect(b["flips"]).to eq(a["flips"])
      expect(b["best_assign"]).to eq(a["best_assign"])
      expect(wassat_stop_requested?(old_stop)).to eq(true)


spec_summary
