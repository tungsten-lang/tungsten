# Preprocessing specs: the four techniques, their proof obligations, the
# elimination stack, and the known edge-case traps.
#
# The independent checker is imported from its own bit for the certificate
# regressions: every UNSAT fixture's proof is replayed by tungsten-wrat
# in-process. The two bits still share no parser or checking code — the
# spec merely runs both.

use spec
use wassat
use ../../tungsten-wrat/lib/wrat

# Probing target: assuming x propagates a and -a, so -x is implied; y then
# follows from (x | y).
PROBE_FAILS = "p cnf 3 3\n-1 2 0\n-1 -2 0\n1 3 0\n"

# a == b through an SCC of the binary implication graph, plus pressure that
# keeps the instance satisfiable.
EQUIV_AB = "p cnf 3 4\n-1 2 0\n-2 1 0\n1 3 0\n-2 -3 0\n"

# x => y => -x and -x => z => x: the implication graph puts x and -x in one
# SCC, which refutes the formula outright.
EQUIV_CONTRA = "p cnf 3 4\n-1 2 0\n-2 -1 0\n1 3 0\n-3 1 0\n"

# (a|b) subsumes (a|b|c); (a|b) also strengthens (-a|b|c) to (b|c).
SUBSUME = "p cnf 3 3\n1 2 0\n1 2 3 0\n-1 2 3 0\n"

# v resolves away: (v|a)(-v|b) => (a|b). One resolvent replaces two clauses.
BVE_SIMPLE = "p cnf 3 2\n1 2 0\n-1 3 0\n"

# (v|a|b)(-v|-a|-b): the only resolvent is a tautology, so eliminating v
# must add nothing -- counting or emitting it would be a bug either way.
# Ternary on purpose: binary clauses would be substituted away first.
BVE_TAUT = "p cnf 3 2\n1 2 3 0\n-1 -2 -3 0\n"

# Eliminating 1 produces the contradictory units 2 and -2.  Those units must
# be propagated only after every pivot parent has been deleted, or the first
# can derive a fresh unit on the supposedly eliminated pivot.
BVE_UNIT_COMMIT = "p cnf 2 4\n1 2 0\n-1 2 0\n1 -2 0\n-1 -2 0\n"

# Exact y = (x2 & x3), plus three positive and one negative non-definition
# occurrence. Full BVE forms ten non-tautological cross-products for seven
# parents and is rejected; the definition-aware basis forms exactly seven:
# (P_i|x2), (P_i|x3), and (-x2|-x3|N).
AND2_FACTORED = "p cnf 7 7\n1 -2 -3 0\n-1 2 0\n-1 3 0\n1 4 0\n1 5 0\n1 6 0\n-1 7 0\n"

# Same shape with a negative output literal and a signed second input:
# -y = (x2 & -x3). This catches orientation mistakes that a positive-only
# gate corpus would leave invisible.
AND2_NEGATIVE_OUTPUT = "p cnf 7 7\n-1 -2 3 0\n1 2 0\n1 -3 0\n-1 4 0\n-1 5 0\n-1 6 0\n1 7 0\n"

AND2_INCOMPLETE = "p cnf 7 6\n1 -2 -3 0\n-1 2 0\n1 4 0\n1 5 0\n1 6 0\n-1 7 0\n"

# One nine-literal positive-output occurrence yields two nine-literal
# resolvents: 18 new literals versus 16 old, exactly +2.  The current
# arity-minus-one policy permits only +1 and must reject this boundary.
AND2_GROWTH_TWO = "p cnf 11 4\n1 -2 -3 0\n-1 2 0\n-1 3 0\n1 4 5 6 7 8 9 10 11 0\n"

# The two extra positive-output clauses produce unit resolvents 2 and 3.
# Propagating either while the gate base is still live can derive unit 1 and
# leave that fresh clause behind after variable 1 is marked eliminated.
AND2_UNIT_COMMIT = "p cnf 3 5\n1 -2 -3 0\n-1 2 0\n-1 3 0\n1 2 0\n1 3 0\n"

PHP32_PRE = "p cnf 6 9\n1 2 0\n3 4 0\n5 6 0\n-1 -3 0\n-1 -5 0\n-3 -5 0\n-2 -4 0\n-2 -6 0\n-4 -6 0\n"

DUPLICATES = "p cnf 3 3\n1 1 2 0\n-1 3 3 0\n-2 -3 0\n"

# Helper-lifetime regression: 1 == 2 through an SCC, then the ternary blocks
# force 1 true and 2 false, so the formula is UNSAT and every (-2 ...) clause
# is rewritten citing the equivalence helper (2 | -1). A bug once rewrote the
# helpers themselves into tautologies and deleted them while later rewritten
# clauses still cited their ids — both certificate dialects failed the
# independent checkers ("step N is not redundant").
HELPER_LIFETIME = "p cnf 4 10\n-1 2 0\n-2 1 0\n1 3 4 0\n1 3 -4 0\n1 -3 4 0\n1 -3 -4 0\n-2 3 4 0\n-2 3 -4 0\n-2 -3 4 0\n-2 -3 -4 0\n"

# BVE resolvent hash-collision regression (hermetic reconstruction of the
# 54-var/84-clause fixture). Eliminating variable 1 forms two DISTINCT
# 14-literal resolvents that hash to the same 64-bit XOR value; a hash-only
# dedup drops one, the reduced formula loses equisatisfiability, and the
# reconstructed model fails the original-formula guard (CaDiCaL says SAT).
# The exact clause set is faithful to /private/tmp/wassat-bve-hash-collision.cnf.
-> bve_hash_collision_cnf
  taut_vars = [6, 7, 8, 9, 11, 12, 13, 14, 17, 18, 21, 22, 24,
               25, 28, 29, 31, 32, 33, 37, 38, 41, 44, 50, 52, 53, 54]
  lines = ["p cnf 54 84"]
  lines.push("1 6 7 8 9 11 12 13 14 17 18 21 22 24 0")
  lines.push("1 25 28 29 31 32 33 37 38 41 44 50 52 53 0")
  lines.push("-1 54 0")
  taut_vars.each -> (v)
    lines.push("[v] -[v] 0")
    lines.push("[v] -[v] 0")
    lines.push("[v] -[v] 0")
  lines.join("\n") + "\n"

# Directly exercise the native distinct-resolvent index with a deliberately
# tiny hash/header capacity.  Pivot 1 has two positive clauses and one
# negative clause, producing the two distinct resolvents (2|4) and (3|4).
# The packed output has ample room; only the independent hash/header bound
# should reject the second result.
-> bve_native_hash_boundary(hashcap)
  fla = i64[6]
  fla[0] = 1
  fla[1] = 2
  fla[2] = 1
  fla[3] = 3
  fla[4] = -1
  fla[5] = 4
  fcs = i64[3]
  fcl = i64[3]
  falive = i64[3]
  ftaut = i64[3]
  ci = 0
  while ci < 3
    fcs[ci] = 2 * ci
    fcl[ci] = 2
    falive[ci] = 1
    ci += 1

  och = i64[10]
  i = 0
  while i < och.size
    och[i] = -1
    i += 1
  ocn = i64[6]
  ocv = i64[6]
  node = 0
  ci = 0
  while ci < 3
    j = 0
    while j < 2
      lit = fla[fcs[ci] + j]
      li = 2 * lit.abs
      li += 1 if lit < 0
      ocn[node] = och[li]
      ocv[node] = ci
      och[li] = node
      node += 1
      j += 1
    ci += 1

  lstamp = i64[10]
  hbuf = i64[hashcap]
  hpos = i64[hashcap]
  out = i64[32]
  pm = i64[13]
  pm[0] = 1
  pm[1] = 0
  pm[2] = 16
  pm[3] = 32
  pm[6] = hashcap
  wassat_pre_bve_scan(fla, fcs, fcl, falive, ftaut, och, ocn, ocv,
                      lstamp, hbuf, hpos, out, pm, 0)
  [pm[4], pm[5]]

# Exercise only the gate pass, without allowing general BVE to make the same
# small fixture disappear afterwards.
-> and2_artifact(text, proof_mode)
  f = wassat_parse_cnf(text)
  pre = WassatPreprocess.new(f["nvars"], f["clauses"], proof_mode, nil)
  pre.init_budget
  pre.intake
  z = pre.run_and2_bve
  pre.artifact

-> model_from_mask(nvars, pivot, mask)
  out = []
  v = 1
  bit = 0
  while v <= nvars
    if v == pivot
      out.push(0 - v)
    else
      out.push(((mask >> bit) & 1) == 1 ? v : 0 - v)
      bit += 1
    v += 1
  out

-> and2_projection_exact?(text, pivot)
  f = wassat_parse_cnf(text)
  art = and2_artifact(text, WASSAT_PROOF_WRAT)
  reduced = { "nvars": f["nvars"], "clauses": art["clauses"] }
  ok = art["stats"]["and2_eliminated"] == 1
  limit = 1 << (f["nvars"] - 1)
  mask = 0
  while mask < limit && ok
    m = model_from_mask(f["nvars"], pivot, mask)
    red_sat = wassat_model_satisfies?(reduced, m)
    mfalse = m.dup
    mfalse[pivot - 1] = 0 - pivot
    mtrue = m.dup
    mtrue[pivot - 1] = pivot
    orig_sat = wassat_model_satisfies?(f, mfalse) || wassat_model_satisfies?(f, mtrue)
    ok = false unless red_sat == orig_sat
    if red_sat
      recon = wassat_reconstruct_model(art["stack"], m, f["nvars"])
      ok = false unless wassat_model_satisfies?(f, recon)
    mask += 1
  ok

describe "Wassat preprocessing" ->

  context "failed-literal probing" ->
    it "derives the negation of a failed literal and cascades it" ->
      art = wassat_preprocess(PROBE_FAILS, WASSAT_PROOF_WRAT)
      expect(art["status"]).to eq(0)
      expect(art["stats"]["probes_failed"] >= 1).to eq(true)
      r = wassat_solve_preprocessed(PROBE_FAILS, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(PROBE_FAILS)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "runs no probes when every variable is already assigned" ->
      art = wassat_preprocess("p cnf 1 1\n1 0\n", WASSAT_PROOF_WRAT)
      expect(art["stats"]["probes"]).to eq(0)

  context "equivalent-literal substitution" ->
    it "substitutes an SCC through its representative" ->
      art = wassat_preprocess(EQUIV_AB, WASSAT_PROOF_WRAT)
      expect(art["stats"]["vars_substituted"] >= 1).to eq(true)
      r = wassat_solve_preprocessed(EQUIV_AB, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(EQUIV_AB)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "refutes on the spot when x and -x share an SCC" ->
      art = wassat_preprocess(EQUIV_CONTRA, WASSAT_PROOF_WRAT)
      expect(art["status"]).to eq(-1)
      last = art["wrat"][art["wrat"].size - 1]
      toks = wassat_tokenize(last)
      expect(toks[1]).to eq("0")
      plain = wassat_solve(EQUIV_CONTRA)
      expect(plain["sat"]).to eq(false)

  context "subsumption and strengthening" ->
    it "deletes subsumed clauses and strengthens self-subsumed ones" ->
      art = wassat_preprocess(SUBSUME, WASSAT_PROOF_WRAT)
      expect(art["stats"]["clauses_subsumed"] >= 1).to eq(true)
      expect(art["stats"]["clauses_strengthened"] >= 1).to eq(true)
      r = wassat_solve_preprocessed(SUBSUME, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(SUBSUME)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

  context "bounded variable elimination" ->
    it "eliminates a variable and reconstructs its value in the model" ->
      art = wassat_preprocess(BVE_SIMPLE, WASSAT_PROOF_WRAT)
      expect(art["stats"]["vars_eliminated"] >= 1).to eq(true)
      r = wassat_solve_preprocessed(BVE_SIMPLE, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(BVE_SIMPLE)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "skips tautological resolvents without counting or emitting them" ->
      art = wassat_preprocess(BVE_TAUT, WASSAT_PROOF_WRAT)
      expect(art["stats"]["vars_eliminated"] >= 1).to eq(true)
      # both originals deleted, the tautological resolvent never added
      kept = 0
      art["clauses"].each -> (c)
        kept += 1
      expect(kept).to eq(0)
      r = wassat_solve_preprocessed(BVE_TAUT, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(BVE_TAUT)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "keeps distinct resolvents that share an XOR hash (collision safety)" ->
      text = bve_hash_collision_cnf
      f = wassat_parse_cnf(text)
      expect(f["clauses"].size).to eq(84)
      # SAT preservation: the reduced formula must stay satisfiable, and the
      # reconstructed model must satisfy the ORIGINAL formula. A hash-only
      # dedup drops a required resolvent and this reconstruction fails.
      r = wassat_solve_preprocessed(text, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "rejects atomically at the independent hash-position capacity" ->
      bounded = bve_native_hash_boundary(1)
      expect(bounded[0]).to eq(0)
      expect(bounded[1]).to eq(1)
      exact = bve_native_hash_boundary(2)
      expect(exact[0]).to eq(1)
      expect(exact[1]).to eq(2)

    it "rejects advertised output caps larger than the physical buffer" ->
      bin = env("WASSAT_TEST_BIN")
      bin = "bits/tungsten-wassat/bin/wassat" if bin == nil || bin == ""
      cnf = "/tmp/wassat-bve-outcap-boundary.cnf"
      z = write_file(cnf, BVE_SIMPLE)
      # The exact physical boundary remains a valid lowering/no-op override.
      ok = system("(env WASSAT_BVE_OUTCAP=131072 " + bin + " " + cnf +
                  " --proof /tmp/wassat-bve-outcap-boundary.wrat" +
                  " > /tmp/wassat-bve-outcap-boundary.out 2>&1);" +
                  " c=$?; test $c -eq 10")
      expect(ok).to eq(true)
      [1000000, 2000000000].each -> (cap)
        out = "/tmp/wassat-bve-outcap-[cap].out"
        rc = system("env WASSAT_BVE_OUTCAP=[cap] " + bin + " " + cnf +
                    " --proof /tmp/wassat-bve-outcap-[cap].wrat" +
                    " > " + out + " 2>&1")
        expect(rc).to eq(false)
        msg = read_file(out)
        expect(msg.index("WASSAT_BVE_OUTCAP needs 1024..131072") != nil).to eq(true)

    it "leaves no live clause mentioning an eliminated variable" ->
      art = wassat_preprocess(SUBSUME, WASSAT_PROOF_WRAT)
      gone = art["gone"]
      ok = true
      art["clauses"].each -> (c)
        c.each -> (l)
          ok = false unless gone[l.abs] == 0
      expect(ok).to eq(true)

    it "deletes the pivot atomically before propagating unit resolvents" ->
      f = wassat_parse_cnf(BVE_UNIT_COMMIT)
      pre = WassatPreprocess.new(f["nvars"], f["clauses"], WASSAT_PROOF_WRAT, nil)
      pre.init_budget
      pre.intake
      expect(pre.try_eliminate(1)).to eq(true)
      art = pre.artifact
      expect(art["status"]).to eq(-1)
      expect(art["gone"][1]).to eq(1)
      art["clauses"].each -> (clause)
        clause.each -> (lit)
          expect(art["gone"][lit.abs]).to eq(0)
      proof = "wrat 1\n" + art["wrat"].join("\n") + "\n"
      expect(wrat_verify(BVE_UNIT_COMMIT, proof)["verified"]).to eq(true)

  context "definition-aware AND elimination" ->
    it "projects the complete gate exactly for every assignment to its environment" ->
      expect(and2_projection_exact?(AND2_FACTORED, 1)).to eq(true)

    it "handles a negative output and signed inputs" ->
      expect(and2_projection_exact?(AND2_NEGATIVE_OUTPUT, 1)).to eq(true)

    it "does not recognize an incomplete definition" ->
      art = and2_artifact(AND2_INCOMPLETE, WASSAT_PROOF_WRAT)
      expect(art["stats"]["and2_candidates"]).to eq(0)
      expect(art["stats"]["and2_eliminated"]).to eq(0)

    it "rejects the exact +2 literal-growth boundary" ->
      art = and2_artifact(AND2_GROWTH_TWO, WASSAT_PROOF_WRAT)
      expect(art["stats"]["and2_candidates"]).to eq(1)
      expect(art["stats"]["and2_eliminated"]).to eq(0)
      expect(art["gone"][1]).to eq(0)

    it "retires the pivot before propagating unit resolvents" ->
      f = wassat_parse_cnf(AND2_UNIT_COMMIT)
      art = and2_artifact(AND2_UNIT_COMMIT, WASSAT_PROOF_WRAT)
      expect(art["stats"]["and2_eliminated"]).to eq(1)
      expect(art["gone"][1]).to eq(1)
      art["clauses"].each -> (clause)
        clause.each -> (lit)
          expect(art["gone"][lit.abs]).to eq(0)
      s = Wassat.new(f["nvars"], art["clauses"], WASSAT_PROOF_NONE, 0)
      r = s.solve_budget(0)
      expect(r["sat"]).to eq(true)
      model = wassat_reconstruct_model(art["stack"], r["model"], f["nvars"])
      expect(wassat_model_satisfies?(f, model)).to eq(true)

    it "emits a checker-valid prefix before a later refutation" ->
      # The gate pass first emits and propagates its unit resolvents; a
      # disjoint four-clause core then lets CDCL finish.  The independent
      # parser checks that additions-before-deletions and deferred propagation
      # leave a valid combined prefix/search proof.
      body = AND2_UNIT_COMMIT.split("\n")
      lines = ["p cnf 5 9"]
      i = 1
      while i < body.size
        lines.push(body[i]) unless body[i] == ""
        i += 1
      lines.push("4 5 0")
      lines.push("4 -5 0")
      lines.push("-4 5 0")
      lines.push("-4 -5 0")
      text = lines.join("\n") + "\n"
      f = wassat_parse_cnf(text)
      pre = WassatPreprocess.new(f["nvars"], f["clauses"], WASSAT_PROOF_WRAT, nil)
      pre.init_budget
      pre.intake
      z = pre.run_and2_bve
      art = pre.artifact
      expect(art["stats"]["and2_eliminated"]).to eq(1)
      s = Wassat.new(f["nvars"], art["clauses"], WASSAT_PROOF_WRAT, 0)
      s.seed_proof_ids(art["gids"], art["next_gid"])
      r = s.solve_budget(0)
      expect(r["unsat"]).to eq(true)
      proof = wassat_concat_arrays(art["wrat"], r["proof"])
      check = wrat_verify(text, "wrat 1\n" + proof.join("\n") + "\n")
      expect(check["verified"]).to eq(true)

  context "degenerate inputs" ->
    it "accepts the empty formula as trivially satisfiable" ->
      r = wassat_solve_preprocessed("p cnf 3 0\n", WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)

    it "refutes an explicit empty input clause before any search" ->
      art = wassat_preprocess("p cnf 1 1\n0\n", WASSAT_PROOF_WRAT)
      expect(art["status"]).to eq(-1)
      toks = wassat_tokenize(art["wrat"][0])
      expect(toks[1]).to eq("0")
      expect(toks[2]).to eq("1")

    it "handles duplicated literals inside input clauses" ->
      r = wassat_solve_preprocessed(DUPLICATES, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(DUPLICATES)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "rejects implausible header declarations loudly" ->
      expect(-> () wassat_parse_cnf("p cnf 99999999999 1\n1 0\n")).to raise_error
      expect(-> () wassat_parse_cnf("p cnf 2 99999999999\n1 0\n")).to raise_error

    it "native parser (compiled CLI) matches the boxed accept/reject matrix" ->
      # __w_parse_dimacs is compiled-only; drive it through the binary.
      bin = env("WASSAT_TEST_BIN")
      bin = "bits/tungsten-wassat/bin/wassat" if bin == nil || bin == ""
      good = ["p cnf 2 1\n1 -2 0\n", "c hi\np cnf 2 2\n1 0 -2 0\n%\n0\n", "p cnf 3 1\n1 2\n3 0\n"]
      gi = 0
      good.each -> (t)
        a = wassat_parse_cnf(t)
        z = write_file("/tmp/npar_g[gi].cnf", t)
        # An accepted formula exits with a SAT Competition verdict code (10
        # SAT / 20 UNSAT) or 0 for UNKNOWN; only a REJECTED one exits 1, so
        # "was it parsed" is "did it avoid the error exit", not "was it 0".
        ok = system("(" + bin + " /tmp/npar_g[gi].cnf --fast > /tmp/npar_g[gi].out 2>&1); c=$?; test $c -eq 0 -o $c -eq 10 -o $c -eq 20")
        out = read_file("/tmp/npar_g[gi].out")
        expect(ok).to eq(true)
        expect(out.index("s ") != nil).to eq(true)
        expect(out.index("c error") == nil).to eq(true)
        gi += 1
      bad = ["1 0\n", "p cnf 1\n1 0\n", "p xnf 1 1\n1 0\n", "p cnf 1 1\np cnf 1 1\n1 0\n",
             "p cnf2 1\n1 0\n", "p cnf 999999999999999999999 1\n1 0\n",
             "p cnf 1 1\nwat 0\n", "p cnf 1 1\ncat 1 0\n", "p cnf 2 1\n3 0\n",
             "p cnf 1 1\n1\n", "p cnf 1 1\n1 -0\n", "p cnf 1 1\n00 0\n",
             "p cnf 2 2\n1 0\n", "p cnf 2 1\n1 0\n2 0\n", "p cnf 2 1\nx 1 2 0\n"]
      bi = 0
      bad.each -> (t)
        expect(-> () wassat_parse_cnf(t)).to raise_error
        z = write_file("/tmp/npar_b[bi].cnf", t)
        rc = system(bin + " /tmp/npar_b[bi].cnf --fast > /tmp/npar_b[bi].out 2>&1")
        expect(rc).to eq(false)
        out = read_file("/tmp/npar_b[bi].out")
        expect(out.index("c error") != nil).to eq(true)
        bi += 1

    it "accepts tab-separated DIMACS" ->
      f = wassat_parse_cnf("p cnf 2 1\n1\t-2\t0\n")
      expect(f["clauses"].size).to eq(1)
      expect(f["clauses"][0].size).to eq(2)

  context "freeze set" ->
    it "never eliminates or substitutes a frozen variable" ->
      f = wassat_parse_cnf(EQUIV_AB)
      pre = WassatPreprocess.new(f["nvars"], f["clauses"], WASSAT_PROOF_WRAT, nil)
      pre.freeze(1)
      pre.freeze(2)
      art = pre.run
      gone = art["gone"]
      expect(gone[1]).to eq(0)
      expect(gone[2]).to eq(0)

  context "portfolio cancellation" ->
    it "stops a losing rendering at the next bounded checkpoint" ->
      f = wassat_parse_cnf(AND2_FACTORED)
      pre = WassatPreprocess.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, nil)
      stop = i64[1]
      pre.set_stop_cell(stop)
      pre.init_budget
      expect(pre.within_budget).to eq(true)
      z = wassat_stop_cancel(stop)
      expect(pre.within_budget).to eq(false)
      expect(pre.run_and2_bve).to eq(false)

  context "output integrity" ->
    it "rejects a corrupted model against the original formula" ->
      f = wassat_parse_cnf(PROBE_FAILS)
      r = wassat_solve_preprocessed(PROBE_FAILS, WASSAT_PROOF_NONE, 0, 0)
      bad = []
      r["model"].each -> (l)
        bad.push(0 - l)
      expect(wassat_model_satisfies?(f, bad)).to eq(false)

  context "certificates" ->
    it "refutes PHP(3,2) through preprocessing with a hinted prefix" ->
      r = wassat_solve_preprocessed(PHP32_PRE, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["unsat"]).to eq(true)
      expect(r["proof"].size > 0).to eq(true)
      last = r["proof"][r["proof"].size - 1]
      toks = wassat_tokenize(last)
      expect(toks[1]).to eq("0")

    it "substitution certificates survive helper deletion ordering" ->
      r = wassat_solve_preprocessed(HELPER_LIFETIME, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["unsat"]).to eq(true)
      expect(r["pre"]["stats"]["vars_substituted"] >= 1).to eq(true)
      check = wrat_verify(HELPER_LIFETIME, wassat_proof_text(r))
      expect(check["verified"]).to eq(true)

    it "every UNSAT fixture certificate verifies under the independent checker" ->
      fixtures = [EQUIV_CONTRA, PHP32_PRE, HELPER_LIFETIME, "p cnf 1 1\n0\n"]
      ok = true
      fixtures.each -> (text)
        r = wassat_solve_preprocessed(text, WASSAT_PROOF_WRAT, 0, 0)
        if r["unsat"]
          check = wrat_verify(text, wassat_proof_text(r))
          ok = false unless check["verified"] == true
        else
          ok = false
      expect(ok).to eq(true)

    it "agrees with the unpreprocessed solver across the fixture set" ->
      fixtures = [PROBE_FAILS, EQUIV_AB, EQUIV_CONTRA, SUBSUME, BVE_SIMPLE, BVE_TAUT, DUPLICATES, PHP32_PRE]
      ok = true
      fixtures.each -> (text)
        plain = wassat_solve_opts(text, false)
        prep = wassat_solve_preprocessed(text, WASSAT_PROOF_NONE, 0, 0)
        ok = false unless plain["status"] == prep["status"]
        if prep["status"] == 1
          f = wassat_parse_cnf(text)
          ok = false unless wassat_model_satisfies?(f, prep["model"])
      expect(ok).to eq(true)

spec_summary
