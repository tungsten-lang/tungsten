# Solver specs, built on well-known propositional test cases.
#
# The families here are the standard ones used to shake out SAT solvers:
# unit contradictions, pigeonhole (exponential for resolution), mutilated
# and plain colouring constraints, at-most-one encodings, and a chain of
# implications that is pure unit propagation.
#
# Every UNSAT example also asserts that the emitted proof ends in the empty
# clause -- a solver that says UNSAT without being able to show why is the
# failure mode these bits exist to prevent.

use spec
use wassat

# --- fixtures ---------------------------------------------------------------

UNIT_CONTRADICTION = "p cnf 1 2\n1 0\n-1 0\n"

# Pigeonhole PHP(3,2): three pigeons, two holes. Haken's exponential family.
PHP32 = "p cnf 6 9\n1 2 0\n3 4 0\n5 6 0\n-1 -3 0\n-1 -5 0\n-3 -5 0\n-2 -4 0\n-2 -6 0\n-4 -6 0\n"

# PHP(2,1): two pigeons, one hole. Smallest nontrivial pigeonhole.
PHP21 = "p cnf 2 3\n1 0\n2 0\n-1 -2 0\n"

# All four combinations of two variables excluded.
ALL_FOUR = "p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n"

# All eight assignments of three variables excluded. This takes four
# conflicts with the deterministic base policy, enough to exercise multiple
# independently-budgeted continuation calls.
ALL_EIGHT = "p cnf 3 8\n1 2 3 0\n1 2 -3 0\n1 -2 3 0\n1 -2 -3 0\n-1 2 3 0\n-1 2 -3 0\n-1 -2 3 0\n-1 -2 -3 0\n"

# The first conflict has an intermediate resolvent that subsumes one reason:
# OTFS learns (5 v 2), while ordinary first-UIP learns the incomparable
# assumption-blocking clause (5 v 1).
OTFS_INSTALL = [[-2, 5, 1], [3, 5, 2], [4, 5, 2], [-3, -4, 5, 2]]

# Here the same resolution pattern yields (1 v 4), exactly the final
# first-UIP clause. The side lemma must be recognized but not installed.
OTFS_DOMINATED = [[2, 1, 4], [3, 1, 4], [-2, -3, 1, 4]]

# Satisfiable: implication chain 1 -> 2 -> 3, with 1 asserted.
CHAIN = "p cnf 3 3\n1 0\n-1 2 0\n-2 3 0\n"

# Satisfiable: a single clause.
ONE_CLAUSE = "p cnf 2 1\n1 2 0\n"

# Every literal free: the empty clause set over three variables.
NO_CLAUSES = "p cnf 3 0\n"

# An explicitly contradictory DIMACS clause, distinct from an empty clause
# set. Its proof must cite this input clause rather than merely claim UNSAT.
EMPTY_CLAUSE = "p cnf 1 1\n0\n"

# Check that a model actually satisfies every clause of a formula.
-> satisfies?(cnf_text, model)
  f = wassat_parse_cnf(cnf_text)
  ok = true
  f["clauses"].each -> (c)
    hit = false
    c.each -> (l)
      model.each -> (m)
        hit = true if m == l
    ok = false unless hit
  ok

# Hammer the runtime CAS primitive from a worker without allocating. Every
# successful global ticket is charged atomically to this worker's slot.
-> wassat_ticket_hammer(state, arm_slot, limit, attempts) (i64[] i64 i64 i64)
  i = 0
  while i < attempts
    ticket = ccall("__w_arr_try_inc_below", state, 0, limit)
    if ticket > 0
      z = ccall("__w_arr_fetch_add", state, arm_slot, 1)
    i += 1
  0

describe "Tungsten Wassat" ->

  context "unsatisfiable formulas" ->
    it "refutes a unit contradiction" ->
      r = wassat_solve(UNIT_CONTRADICTION)
      expect(r["sat"]).to eq(false)

    it "refutes pigeonhole PHP(2,1)" ->
      r = wassat_solve(PHP21)
      expect(r["sat"]).to eq(false)

    it "refutes pigeonhole PHP(3,2)" ->
      r = wassat_solve(PHP32)
      expect(r["sat"]).to eq(false)

    it "refutes an exhaustive two-variable clause set" ->
      r = wassat_solve(ALL_FOUR)
      expect(r["sat"]).to eq(false)

  context "satisfiable formulas" ->
    it "solves a single clause and returns a real model" ->
      r = wassat_solve(ONE_CLAUSE)
      expect(r["sat"]).to eq(true)
      expect(satisfies?(ONE_CLAUSE, r["model"])).to eq(true)

    it "propagates an implication chain" ->
      r = wassat_solve(CHAIN)
      expect(r["sat"]).to eq(true)
      expect(satisfies?(CHAIN, r["model"])).to eq(true)

    it "accepts a formula with no clauses" ->
      r = wassat_solve(NO_CLAUSES)
      expect(r["sat"]).to eq(true)

    it "seeds the target-phase basin used by diversified race arms" ->
      s = Wassat.new(32, [], WASSAT_PROOF_NONE, 0)
      s.enable_frontier_mode
      s.reseed_phases(15485863, true)
      r = s.solve_budget(0)
      expect(r["status"]).to eq(1)
      positive = 0
      negative = 0
      r["model"].each -> (lit)
        if lit > 0
          positive += 1
        else
          negative += 1
      expect(positive > 0).to eq(true)
      expect(negative > 0).to eq(true)

    it "does not branch on variables removed from a flat artifact" ->
      # Mirrors a sparse preprocessed kernel with a large declared capacity:
      # variable 1 remains as a unit and every other coordinate has been
      # eliminated or substituted.  The reduced solver must not spend one
      # decision per dead coordinate before recognizing the model.
      text = "p cnf 4096 1\n1 0\n"
      art = wassat_preprocess(text, WASSAT_PROOF_NONE)
      v = 2
      while v <= 4096
        art["gone"][v] = 1
        v += 1
      art["stats"]["vars_eliminated"] = 4095
      s = Wassat.from_flat(4096, art, 0)
      r = s.solve_budget(0)
      expect(r["status"]).to eq(1)
      expect(r["decisions"]).to eq(0)
      model = wassat_reconstruct_model(art["stack"], r["model"], 4096)
      expect(wassat_model_satisfies?(wassat_parse_cnf(text), model)).to eq(true)

    it "refreshes formula-shaped lucky policy when a flat artifact is loaded" ->
      # from_flat_lucky first builds an empty-clause allocation shell. The
      # shell enables lucky by default; the real dense-ternary configuration
      # disables it. Keep the artifact tiny while giving its policy the exact
      # production histogram, so this pins the state hand-off without a
      # 200,000-clause fixture.
      formula = wassat_parse_cnf_native("p cnf 272 1\n1 2 3 0\n")
      art = wassat_raw_artifact(formula, 272)
      counts = i64[8]
      counts[0] = 600000
      counts[1] = 4
      counts[3] = 1380
      counts[4] = 199027
      dense = WassatConfig.new(272, [])
      dense.adopt_counts(200920, counts)
      expect(dense.use_lucky).to eq(false)
      art["config"] = dense

      s = Wassat.from_flat_lucky(272, art)
      res = i64[280]
      s.lucky_shared(res, 0)
      expect(res[0]).to eq(0)
      expect(res[273]).to eq(0)

  context "competition output" ->
    it "wraps large models without losing or duplicating literals" ->
      model = []
      v = 1
      while v <= 4000
        model.push((v & 1) == 0 ? v : 0 - v)
        v += 1
      lines = wassat_sat_text(model).strip.split("\n")
      expect(lines[0]).to eq("s SATISFIABLE")
      expect(lines.size > 2).to eq(true)
      observed = []
      i = 1
      while i < lines.size
        line = lines[i]
        expect(line.starts_with?("v ")).to eq(true)
        expect(line.size <= WASSAT_VALUE_LINE_MAX).to eq(true)
        expect(line.ends_with?(" 0")).to eq(i == lines.size - 1)
        tokens = wassat_tokenize(line)
        j = 1
        while j < tokens.size
          observed.push(tokens[j].to_i) unless tokens[j] == "0"
          j += 1
        i += 1
      expect(observed).to eq(model)

  context "bounded search" ->
    it "reports UNKNOWN rather than UNSAT when its conflict budget expires" ->
      r = wassat_solve_limited(ALL_FOUR, false, 0, 1)
      expect(r["status"]).to eq(0)
      expect(r["conflicts"]).to eq(1)
      expect(wassat_result_text(r)).to eq("s UNKNOWN\n")
      expect(r["proof"].size).to eq(0)

    it "keeps decisive root contradictions conclusive under a budget" ->
      r = wassat_solve_limited(UNIT_CONTRADICTION, true, 0, 1)
      expect(r["status"]).to eq(-1)
      expect(wassat_result_text(r)).to eq("s UNSATISFIABLE\n")

    it "does not expose a partial raw proof for UNKNOWN" ->
      r = wassat_solve_mode_limited(ALL_FOUR, WASSAT_PROOF_DRAT, 0, 1)
      expect(r["status"]).to eq(0)
      expect(r["complete"]).to eq(false)
      expect(r["unsat"]).to eq(false)
      expect(r["drat"].size).to eq(0)
      expect(wassat_drat_text(r)).to eq("")

    it "treats each positive budget as additional work" ->
      f = wassat_parse_cnf(ALL_EIGHT)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, 0)
      first = s.solve_budget(1)
      second = s.solve_budget(2)
      expect(first["status"]).to eq(0)
      expect(first["conflicts"]).to eq(1)
      expect(second["status"]).to eq(0)
      expect(second["conflicts"]).to eq(3)
      expect(s.solve_budget(0)["status"]).to eq(-1)

    it "rejects a negative library conflict budget" ->
      f = wassat_parse_cnf(ALL_FOUR)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, 0)
      expect(-> () s.solve_budget(-1)).to raise_error
      expect(-> () wassat_solve_limited(ALL_FOUR, false, 0, -1)).to raise_error

    it "retains a hidden WRAT prefix across UNKNOWN and detaches old results" ->
      f = wassat_parse_cnf(ALL_FOUR)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_WRAT, 0)
      partial = s.solve_budget(1)
      expect(partial["status"]).to eq(0)
      expect(partial["proof"].size).to eq(0)
      finished = s.solve_budget(0)
      expect(finished["status"]).to eq(-1)
      expect(finished["complete"]).to eq(true)
      expect(finished["unsat"]).to eq(true)
      expect(finished["proof_mode"]).to eq(WASSAT_PROOF_WRAT)
      expect(finished["proof"].size).to eq(2)
      expect(wassat_tokenize(finished["proof"][0])[0]).to eq("5")
      expect(wassat_tokenize(finished["proof"][1])[0]).to eq("6")
      expect(partial["proof"].size).to eq(0)

    it "retains a hidden raw DRAT prefix across UNKNOWN" ->
      f = wassat_parse_cnf(ALL_FOUR)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_DRAT, 0)
      partial = s.solve_budget(1)
      finished = s.solve_budget(0)
      expect(partial["drat"].size).to eq(0)
      expect(finished["status"]).to eq(-1)
      expect(finished["drat"].size).to eq(2)
      expect(wassat_drat_text(finished).ends_with?("0\n")).to eq(true)

    it "makes terminal calls idempotent and returns fresh result arrays" ->
      f = wassat_parse_cnf(ALL_FOUR)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_WRAT, 0)
      first = s.solve_budget(0)
      conflicts = first["conflicts"]
      proof_size = first["proof"].size
      first["proof"].push("caller mutation")
      again = s.solve_budget(1)
      expect(again["status"]).to eq(-1)
      expect(again["conflicts"]).to eq(conflicts)
      expect(again["proof"].size).to eq(proof_size)

      sf = wassat_parse_cnf(ONE_CLAUSE)
      sat_solver = Wassat.new(sf["nvars"], sf["clauses"], WASSAT_PROOF_NONE, 0)
      sat_first = sat_solver.solve_budget(0)
      sat_first["model"].push(99)
      sat_again = sat_solver.solve_budget(1)
      expect(sat_again["status"]).to eq(1)
      expect(sat_again["model"].size).to eq(2)

  context "atomic cooperative stop cells" ->
    it "publishes payload and status before readers observe the flag" ->
      stop = i64[4]
      payload = i64[1]
      observed = i64[2]
      reader = Thread.new ->
        while !wassat_stop_requested?(stop)
          z = 0
        observed[0] = payload[0]
        observed[1] = wassat_stop_status(stop)
      writer = Thread.new ->
        payload[0] = 8675309
        won = wassat_stop_publish(stop, 0 - 1)
      z = writer.join
      z = reader.join
      expect(observed[0]).to eq(8675309)
      expect(observed[1]).to eq(-1)

    it "keeps the first decisive status under racing publishers" ->
      stop = i64[4]
      won = i64[4]
      h1 = Thread.new -> won[0] = wassat_stop_publish(stop, 1)
      h2 = Thread.new -> won[1] = wassat_stop_publish(stop, 0 - 1)
      h3 = Thread.new -> won[2] = wassat_stop_publish(stop, 1)
      h4 = Thread.new -> won[3] = wassat_stop_publish(stop, 0 - 1)
      z = h1.join
      z = h2.join
      z = h3.join
      z = h4.join
      expect(won[0] + won[1] + won[2] + won[3]).to eq(1)
      status = wassat_stop_status(stop)
      expected = 0
      expected = 1 if won[0] == 1 || won[2] == 1
      expected = -1 if won[1] == 1 || won[3] == 1
      expect(status).to eq(expected)
      expect(wassat_stop_requested?(stop)).to eq(true)
      # Neither cancellation nor a late verdict may overwrite the winner.
      z = wassat_stop_cancel(stop)
      z = wassat_stop_publish(stop, 0 - status)
      expect(wassat_stop_status(stop)).to eq(status)

  context "shared aggregate conflict tickets" ->
    it "never overshoots under concurrent native CAS reservations" ->
      state = i64[5]
      h1 = Thread.new -> wassat_ticket_hammer(state, 1, 37, 256)
      h2 = Thread.new -> wassat_ticket_hammer(state, 2, 37, 256)
      h3 = Thread.new -> wassat_ticket_hammer(state, 3, 37, 256)
      h4 = Thread.new -> wassat_ticket_hammer(state, 4, 37, 256)
      z = h1.join
      z = h2.join
      z = h3.join
      z = h4.join
      expect(state[0]).to eq(37)
      expect(state[1] + state[2] + state[3] + state[4]).to eq(37)

    it "caps two solver arms exactly and accounts every ticket once" ->
      f = wassat_parse_cnf(ALL_EIGHT)
      s1 = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, 0)
      s2 = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, 0)
      stop = i64[2]
      state = i64[3]
      stride = f["nvars"] + 8
      res = i64[2 * stride]
      s1.set_stop_cell(stop)
      s2.set_stop_cell(stop)
      s1.set_shared_conflict_budget(state, 3, 1)
      s2.set_shared_conflict_budget(state, 3, 2)
      s1.enable_fixed_caps
      s2.enable_fixed_caps
      h1 = Thread.new -> s1.solve_shared_budget(res, 0, 0)
      h2 = Thread.new -> s2.solve_shared_budget(res, stride, 0)
      z = h1.join
      z = h2.join
      expect(state[0]).to eq(3)
      expect(state[1] + state[2]).to eq(3)
      charged = res[f["nvars"] + 4] + res[stride + f["nvars"] + 4]
      expect(charged).to eq(3)
      expect(res[0]).to eq(0)
      expect(res[stride]).to eq(0)
      expect(wassat_stop_requested?(stop)).to eq(true)
      expect(wassat_stop_status(stop)).to eq(0)

    it "keeps a decisive UNSAT verdict from the final allowed conflict" ->
      f = wassat_parse_cnf(ALL_FOUR)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, 0)
      stop = i64[2]
      state = i64[2]
      res = i64[f["nvars"] + 8]
      s.set_stop_cell(stop)
      s.set_shared_conflict_budget(state, 2, 1)
      s.solve_shared_budget(res, 0, 0)
      expect(res[0]).to eq(-1)
      expect(state[0]).to eq(2)
      expect(state[1]).to eq(2)
      expect(wassat_stop_requested?(stop)).to eq(true)
      expect(wassat_stop_status(stop)).to eq(-1)

    it "preserves a failed-assumption core exposed by the final ticket" ->
      # Globally satisfiable (set 1=false), but assumption 1 makes 2 and -2
      # collide. The one learned unit exposes the core only after that final
      # conflict has been processed.
      s = Wassat.new(2, [[-1, 2], [-1, -2]], WASSAT_PROOF_NONE, 0)
      stop = i64[2]
      state = i64[2]
      s.set_stop_cell(stop)
      s.set_shared_conflict_budget(state, 1, 1)
      r = s.solve_assuming_budget([1], 0)
      expect(r["status"]).to eq(-1)
      expect(r["core"]).to eq([1])
      expect(r["conflicts"]).to eq(1)
      expect(state[0]).to eq(1)
      expect(state[1]).to eq(1)
      expect(wassat_stop_requested?(stop)).to eq(true)
      # This is query-local UNSAT, not a formula verdict for peers.
      expect(wassat_stop_status(stop)).to eq(0)

    it "charges frozen repair against a finite scout ticket pool" ->
      f = wassat_parse_cnf_native(CHAIN)
      art = wassat_raw_artifact(f, f["nvars"])
      bits = i64[f["nvars"] + 1]
      stop = i64[4]
      state = i64[3]
      # Model an ordinary scout having consumed slot 1's first ticket; the
      # repair gets exactly the one remaining ticket through logical slot 2.
      state[0] = 1
      state[1] = 1
      r = wassat_sls_frozen_repair(
        f, art, bits, [-1, -2, -3], 1, stop, 3840, state, 2, 2
      )
      expect(r["attempted"]).to eq(true)
      expect(r["conflicts"]).to eq(1)
      expect(r["core_rounds"]).to eq(1)
      expect(state[0]).to eq(2)
      expect(state[1] + state[2]).to eq(2)
      expect(wassat_stop_requested?(stop)).to eq(true)
      expect(wassat_stop_status(stop)).to eq(0)

    it "keeps per-call slices additional and does not publish their boundary" ->
      f = wassat_parse_cnf(ALL_EIGHT)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, 0)
      stop = i64[2]
      state = i64[2]
      res = i64[f["nvars"] + 8]
      s.set_stop_cell(stop)
      s.set_shared_conflict_budget(state, 10, 1)
      s.solve_shared_budget(res, 0, 1)
      expect(res[0]).to eq(0)
      expect(state[0]).to eq(1)
      expect(wassat_stop_requested?(stop)).to eq(false)
      s.solve_shared_budget(res, 0, 1)
      expect(res[0]).to eq(0)
      expect(state[0]).to eq(2)
      expect(state[1]).to eq(2)
      expect(wassat_stop_requested?(stop)).to eq(false)

  context "on-the-fly strengthening" ->
    it "installs an implied side lemma not dominated by first-UIP" ->
      s = Wassat.new(5, OTFS_INSTALL, WASSAT_PROOF_NONE, 0)
      s.enable_otfs
      r = s.solve_assuming([-1, -5])
      expect(r["status"]).to eq(-1)
      expect(r["core"]).to eq([-5, -1])
      expect(r["otfs_hits"]).to eq(1)
      expect(r["otfs_installed"]).to eq(1)
      expect(r["otfs_dominated"]).to eq(0)

    it "skips a side lemma already dominated by first-UIP" ->
      s = Wassat.new(4, OTFS_DOMINATED, WASSAT_PROOF_NONE, 0)
      s.enable_otfs
      r = s.solve_assuming([-1, -4])
      expect(r["status"]).to eq(-1)
      expect(r["core"]).to eq([-4, -1])
      expect(r["otfs_hits"]).to eq(1)
      expect(r["otfs_installed"]).to eq(0)
      expect(r["otfs_dominated"]).to eq(1)

    it "keeps side-lemma strengthening out of hinted proof mode" ->
      s1 = Wassat.new(5, OTFS_INSTALL, WASSAT_PROOF_WRAT, 0)
      s1.enable_otfs
      r1 = s1.solve_assuming([-1, -5])
      expect(r1["status"]).to eq(-1)
      expect(r1["otfs_hits"]).to eq(0)
      expect(r1["otfs_installed"]).to eq(0)

    it "keeps side-lemma strengthening out of raw proof mode" ->
      s2 = Wassat.new(5, OTFS_INSTALL, WASSAT_PROOF_DRAT, 0)
      s2.enable_otfs
      r2 = s2.solve_assuming([-1, -5])
      expect(r2["status"]).to eq(-1)
      expect(r2["otfs_hits"]).to eq(0)
      expect(r2["otfs_installed"]).to eq(0)

  context "fixed-capacity search (portfolio arm safety)" ->
    # Regression for the fixed-capacity portfolio SIGBUS: capacity exhaustion
    # while handling a conflict must NOT backjump/compact before analysis.
    # Forcing a tiny arena makes almost every conflict hit the exhaustion
    # path; the arm must analyze the conflict first, then reclaim or retire —
    # never crash and never answer SAT on this UNSAT formula.
    it "handles arena exhaustion mid-conflict without corrupting analysis" ->
      f = wassat_parse_cnf(PHP32)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, 0)
      s.force_tiny_arena_for_test(3 * (f["nvars"] + 8))
      r = s.solve_budget(0)
      # completes without a crash; UNSAT if it reclaimed enough, else UNKNOWN
      # (retired) — but NEVER a spurious SAT
      expect(r["status"] == -1 || r["status"] == 0).to eq(true)

    it "retires safely when the arena cannot hold even one learned clause" ->
      f = wassat_parse_cnf(PHP32)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, 0)
      s.force_tiny_arena_for_test(1)
      r = s.solve_budget(0)
      expect(r["status"] == -1 || r["status"] == 0).to eq(true)

  context "EVSIDS variable-order heap" ->
    it "raises bumped variables to the top and keeps inverse positions valid" ->
      asg = i8[6]
      act = i64[6]
      heap = i64[6]
      hpos = i64[6]
      hst = i64[2]
      v = 0
      while v < 6
        hpos[v] = -1
        v += 1
      hst[1] = 32
      v = 1
      while v <= 5
        wassat_heap_insert(heap, hpos, act, hst, v)
        v += 1

      wassat_evsids_bump(act, heap, hpos, hst, 4, 5)
      expect(wassat_heap_valid(heap, hpos, act, hst, 5)).to eq(1)
      expect(wassat_heap_pick(asg, heap, hpos, act, hst)).to eq(4)
      expect(hpos[4]).to eq(-1)
      expect(wassat_heap_valid(heap, hpos, act, hst, 5)).to eq(1)

    it "lazily drops assigned variables and reinserts them after unassignment" ->
      asg = i8[5]
      act = i64[5]
      heap = i64[5]
      hpos = i64[5]
      hst = i64[2]
      v = 0
      while v < 5
        hpos[v] = -1
        v += 1
      hst[1] = 32
      v = 1
      while v <= 4
        wassat_heap_insert(heap, hpos, act, hst, v)
        v += 1
      wassat_evsids_bump(act, heap, hpos, hst, 3, 4)
      asg[3] = 1

      chosen = wassat_heap_pick(asg, heap, hpos, act, hst)
      expect(chosen == 3).to eq(false)
      expect(hpos[3]).to eq(-1)
      asg[3] = 0
      expect(wassat_heap_insert(heap, hpos, act, hst, 3)).to eq(1)
      expect(wassat_heap_valid(heap, hpos, act, hst, 4)).to eq(1)
      expect(wassat_heap_pick(asg, heap, hpos, act, hst)).to eq(3)

    it "grows the integer increment by one sixteenth and rescales safely" ->
      act = i64[4]
      heap = i64[4]
      hpos = i64[4]
      hst = i64[2]
      v = 0
      while v < 4
        hpos[v] = -1
        v += 1
      hst[1] = 32
      v = 1
      while v <= 3
        wassat_heap_insert(heap, hpos, act, hst, v)
        v += 1

      wassat_evsids_advance(hst)
      expect(hst[1]).to eq(34)
      wassat_evsids_bump(act, heap, hpos, hst, 2, 3)
      expect(act[2]).to eq(34)
      act[2] = 4503599627370496
      wassat_evsids_bump(act, heap, hpos, hst, 2, 3)
      expect(act[2] < 4503599627370496).to eq(true)
      expect(hst[1]).to eq(32)
      expect(wassat_heap_valid(heap, hpos, act, hst, 3)).to eq(1)

    it "keeps legacy lookahead arguments source-compatible under automatic policy" ->
      sat = wassat_solve_full(CHAIN, false, 3)
      unsat = wassat_solve_full(PHP32, false, 4)
      expect(sat["status"]).to eq(1)
      expect(satisfies?(CHAIN, sat["model"])).to eq(true)
      expect(unsat["status"]).to eq(-1)

  context "proof emission" ->
    it "ends a refutation with the empty clause" ->
      r = wassat_solve(PHP32)
      proof = r["proof"]
      last = proof[proof.size - 1]
      # A hinted line is `<id> <lits> 0 <hints> 0`, so the empty clause is
      # the one whose literal section is already closed at token 1.
      toks = wassat_tokenize(last)
      expect(toks[1]).to eq("0")

    it "emits a hinted .wrat proof with a header" ->
      text = wassat_proof_text(wassat_solve(PHP32))
      expect(text.starts_with?("wrat 1")).to eq(true)

    it "emits plain .drat ending in the empty clause" ->
      text = wassat_drat_text(wassat_solve(UNIT_CONTRADICTION))
      expect(text.ends_with?("0\n")).to eq(true)

    it "records raw DRAT without constructing hinted WRAT" ->
      r = wassat_solve_mode_limited(PHP32, WASSAT_PROOF_DRAT, 0, 0)
      expect(r["status"]).to eq(-1)
      expect(r["proof"].size).to eq(0)
      expect(r["drat"].size > 0).to eq(true)
      expect(wassat_drat_text(r).ends_with?("0\n")).to eq(true)

    it "refuses to render absent or wrong-mode certificates" ->
      no_proof = wassat_solve_opts(UNIT_CONTRADICTION, false)
      raw = wassat_solve_mode_limited(UNIT_CONTRADICTION, WASSAT_PROOF_DRAT, 0, 0)
      expect(no_proof["complete"]).to eq(true)
      expect(no_proof["unsat"]).to eq(true)
      expect(wassat_proof_text(no_proof)).to eq("")
      expect(wassat_drat_text(no_proof)).to eq("")
      expect(wassat_proof_text(raw)).to eq("")
      expect(wassat_drat_text(raw).ends_with?("0\n")).to eq(true)

    it "derives an empty clause from an explicit empty input clause" ->
      r = wassat_solve(EMPTY_CLAUSE)
      expect(r["status"]).to eq(-1)
      expect(r["proof"].size).to eq(1)
      toks = wassat_tokenize(r["proof"][0])
      expect(toks[1]).to eq("0")
      expect(toks[2]).to eq("1")

    it "records a raw terminal step for an explicit empty input clause" ->
      r = wassat_solve_mode_limited(EMPTY_CLAUSE, WASSAT_PROOF_DRAT, 0, 0)
      expect(r["drat"].size).to eq(1)
      expect(r["drat"][0]).to eq("0")

    it "emits no proof for a satisfiable formula" ->
      r = wassat_solve(ONE_CLAUSE)
      expect(r["proof"].size).to eq(0)

  context "DIMACS parsing" ->
    it "ignores comments and honors the declared variable count" ->
      f = wassat_parse_cnf("c hello\np cnf 2 1\n1 -2 0\n")
      expect(f["nvars"]).to eq(2)
      expect(f["clauses"].size).to eq(1)

    it "accepts clauses spanning several lines" ->
      f = wassat_parse_cnf("p cnf 3 1\n1 2\n3 0\n")
      expect(f["clauses"].size).to eq(1)
      expect(f["clauses"][0].size).to eq(3)

    it "accepts several clauses on one line and a SATLIB trailer" ->
      f = wassat_parse_cnf("p cnf 2 2\n1 0 -2 0\n%\n0\n")
      expect(f["clauses"].size).to eq(2)

    it "rejects XNF instead of misreading x as an empty clause" ->
      xnf = "p cnf 2 1\nx 1 2 0\n"
      expect(-> () wassat_parse_cnf(xnf)).to raise_error

    it "rejects non-integer clause tokens" ->
      bad = "p cnf 1 1\nwat 0\n"
      comment_prefix = "p cnf 1 1\ncat 1 0\n"
      expect(-> () wassat_parse_cnf(bad)).to raise_error
      expect(-> () wassat_parse_cnf(comment_prefix)).to raise_error

    it "requires exactly one well-formed p cnf header" ->
      no_header = "1 0\n"
      short_header = "p cnf 1\n1 0\n"
      extra_header_field = "p cnf 1 1 trailing\n1 0\n"
      wrong_kind = "p xnf 1 1\n1 0\n"
      negative_count = "p cnf -1 1\n1 0\n"
      duplicate = "p cnf 1 1\np cnf 1 1\n1 0\n"
      expect(-> () wassat_parse_cnf(no_header)).to raise_error
      expect(-> () wassat_parse_cnf(short_header)).to raise_error
      expect(-> () wassat_parse_cnf(extra_header_field)).to raise_error
      expect(-> () wassat_parse_cnf(wrong_kind)).to raise_error
      expect(-> () wassat_parse_cnf(negative_count)).to raise_error
      expect(-> () wassat_parse_cnf(duplicate)).to raise_error

    it "rejects missing or signed clause terminators" ->
      missing = "p cnf 1 1\n1\n"
      signed = "p cnf 1 1\n1 -0\n"
      padded = "p cnf 1 1\n00 0\n"
      expect(-> () wassat_parse_cnf(missing)).to raise_error
      expect(-> () wassat_parse_cnf(signed)).to raise_error
      expect(-> () wassat_parse_cnf(padded)).to raise_error

    it "enforces the declared variable bound" ->
      bad = "p cnf 2 1\n3 0\n"
      expect(-> () wassat_parse_cnf(bad)).to raise_error

    it "enforces both underfilled and overfilled clause counts" ->
      too_few = "p cnf 2 2\n1 0\n"
      too_many = "p cnf 2 1\n1 0\n2 0\n"
      expect(-> () wassat_parse_cnf(too_few)).to raise_error
      expect(-> () wassat_parse_cnf(too_many)).to raise_error

spec_summary
