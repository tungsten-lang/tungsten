use spec
use ../lib/wassat

-> spec_flat_formula(text)
  f = wassat_parse_cnf(text)
  clauses = f["clauses"]
  total = 0
  clauses.each -> (clause)
    total += clause.size
  lits = i64[total]
  offs = i64[clauses.size]
  lens = i64[clauses.size]
  offset = 0
  index = 0
  clauses.each -> (clause)
    offs[index] = offset
    lens[index] = clause.size
    clause.each -> (lit)
      lits[offset] = lit
      offset += 1
    index += 1
  f["flat_lits"] = lits
  f["flat_offs"] = offs
  f["flat_lens"] = lens
  f["flat_ncl"] = clauses.size
  f["flat_nlits"] = total
  f

describe "Wassat focused/stable mode split, target-phase protection, and structural pruning" ->

  context "focused-only and stable-only portfolio arms" ->
    it "assigns 2 alternating arms, 1 focused-only arm, and 1 stable-only arm in a 4-arm race" ->
      cnf = "p cnf 6 6\n1 2 3 0\n-1 4 0\n-2 5 0\n-3 6 0\n-4 -5 0\n-5 -6 0\n"
      f = spec_flat_formula(cnf)
      art = wassat_raw_artifact(f, f["nvars"])
      race = wassat_race_build(f["nvars"], art, 4, f)
      solvers = race["solvers"]
      expect(solvers.size >= 4).to eq(true)
      expect(solvers[0].focused_only?).to eq(false)
      expect(solvers[0].stable_only?).to eq(false)
      expect(solvers[1].focused_only?).to eq(false)
      expect(solvers[1].stable_only?).to eq(false)
      expect(solvers[2].focused_only?).to eq(true)
      expect(solvers[2].stable_only?).to eq(false)
      expect(solvers[3].focused_only?).to eq(false)
      expect(solvers[3].stable_only?).to eq(true)

  context "target-phase (@bphase / @best_phase) protection across rephase" ->
    it "preserves @best_phase across Inverted/Original rephases and keeps @bphase intact on focused-only arms" ->
      s = Wassat.new(4, [[1, 2], [3, 4]], WASSAT_PROOF_NONE, 0)
      s.enable_focused_only
      s.set_phases([1, 2, 3, 4])
      expect(s.best_phase_of(1)).to eq(1)
      expect(s.target_phase_of(1)).to eq(1)

      # Step 0 (Best): restores @best_phase
      s.rephase
      expect(s.saved_phase_of(1)).to eq(1)
      expect(s.target_phase_of(1)).to eq(1)
      expect(s.best_phase_of(1)).to eq(1)

      # Step 1 (Walk) and Step 2 (Inverted -1)
      s.rephase
      s.rephase
      # After Inverted (-1) rephase: @phase is -1, but @best_phase and focused-only @bphase remain +1!
      expect(s.saved_phase_of(1)).to eq(-1)
      expect(s.best_phase_of(1)).to eq(1)
      expect(s.target_phase_of(1)).to eq(1)

      # Step 3 (Best) restores @phase back to +1 from @best_phase
      s.rephase
      expect(s.saved_phase_of(1)).to eq(1)
      expect(s.target_phase_of(1)).to eq(1)

  context "Syntactic Control-Variable identification" ->
    it "ranks global cluster-bridging control variables above local variables" ->
      # Variable 1 bridges variables across clusters (2..60), while others are local
      lines = ["p cnf 120 12"]
      lines.push("1 2 20 0")
      lines.push("1 40 60 0")
      lines.push("1 80 100 0")
      lines.push("-1 3 25 0")
      lines.push("-1 45 65 0")
      lines.push("-1 85 115 0")
      lines.push("10 11 0")
      lines.push("-10 11 0")
      lines.push("11 12 0")
      lines.push("-11 -12 0")
      lines.push("12 13 0")
      lines.push("-12 13 0")
      f = spec_flat_formula(lines.join("\n") + "\n")
      res = wassat_identify_control_vars(120, f, 8)
      expect(res["control_vars"].empty?).to eq(false)
      expect(res["control_vars"][0]).to eq(1)

      s = Wassat.from_flat(120, wassat_raw_artifact(f, 120), 0)
      s.enable_vmtf
      s.promote_control_vars(res["control_vars"])
      expect(s.pick_branch).to eq(1)

  context "Cardinality / EO domain case-split and sequential-counter chain propagation" ->
    it "derives constructive-dilemma units, single-survivor binaries, and monotone chain guards" ->
      # EO group {1, 2, 3}: (1 v 2 v 3) and pairwise mutex (-1 -2), (-1 -3), (-2 -3).
      # All three imply 7: (-1 7), (-2 7), (-3 7) -> constructive dilemma forces unit 7!
      # Branches 1 and 2 imply 8: (-1 8), (-2 8) -> single-survivor implies (3 v 8)!
      # Monotone chain 4 -> 5 with guard 6: (4 v -5), (-4 v 5 v 6), and -6 is unit -> (-4 v 5)!
      cnf = [
        "p cnf 8 13",
        "1 2 3 0",
        "-1 -2 0",
        "-1 -3 0",
        "-2 -3 0",
        "-1 7 0",
        "-2 7 0",
        "-3 7 0",
        "-1 8 0",
        "-2 8 0",
        "4 -5 0",
        "-4 5 6 0",
        "-6 0",
        "4 0"
      ].join("\n") + "\n"
      f = spec_flat_formula(cnf)
      card = wassat_extract_cardinality_and_propagate(8, f)
      expect(card["unsat"]).to eq(false)
      expect(card["units"].include?(7)).to eq(true)
      expect(card["units"].include?(5)).to eq(true)
      expect(card["binaries"].include?([3, 8])).to eq(true)

    it "extracts EO-guarded domains, projects multi-step monotone chain cuts, and flattens chain shortcuts" ->
      # Monotone chain 1 <- 2 <- 3 <- 4: (1 v -2), (2 v -3), (3 v -4).
      # Cut-projection guards:
      #   u1 = 5 forbids cuts 0, 1, 2 via (-5 v 2)
      #   u2 = 6 forbids cuts 2, 3, 4 via (-6 v -2)
      #   Together, 5 and 6 leave no valid cut -> derives (-5 v -6)!
      # Flat chain shortcut: 4 => 1 derives direct shortcut (1 v -4).
      # Clause strengthening: (4 v 1 v 7) has 4 => 1, so 4 is dropped -> derives (1 v 7)!
      cnf = [
        "p cnf 7 7",
        "1 -2 0",
        "2 -3 0",
        "3 -4 0",
        "-5 2 0",
        "-6 -2 0",
        "4 1 7 0",
        "5 6 7 0"
      ].join("\n") + "\n"
      f = spec_flat_formula(cnf)
      card = wassat_extract_cardinality_and_propagate(7, f)
      expect(card["unsat"]).to eq(false)
      expect(card["binaries"].include?([-6, -5])).to eq(true)
      expect(card["binaries"].include?([-4, 1])).to eq(true)
      expect(card["binaries"].include?([1, 7])).to eq(true)

  context "DETOUR bidirectional wavefront and macro-transition portal-balance pruning" ->
    it "prunes dead intermediate portal states and extracts a valid DETOUR witness route" ->
      # 3 layers of EO groups:
      # Layer 0: {1, 2}
      # Layer 1: {3, 4}
      # Layer 2: {5, 6}
      # Transitions:
      #   State 1 conflicts with both 3 and 4: (-1 -3), (-1 -4) -> State 1 is dead (-1)!
      #   State 2 -> State 3 is allowed, State 2 conflicts with 4: (-2 -4) -> State 4 is dead (-4)!
      #   State 3 -> State 5 is allowed, State 3 conflicts with 6: (-3 -6) -> State 6 is dead (-6)!
      cnf = [
        "p cnf 6 11",
        "1 2 0", "-1 -2 0",
        "3 4 0", "-3 -4 0",
        "5 6 0", "-5 -6 0",
        "-1 -3 0", "-1 -4 0",
        "-2 -4 0",
        "-3 -6 0",
        "-4 -5 0"
      ].join("\n") + "\n"
      f = spec_flat_formula(cnf)
      det = wassat_detour_prune(6, f)
      expect(det["unsat"]).to eq(false)
      expect(det["units"].include?(-1)).to eq(true)
      expect(det["units"].include?(2)).to eq(true)
      expect(det["units"].include?(3)).to eq(true)
      expect(det["units"].include?(5)).to eq(true)
      expect(det["witness_phases"].include?(2)).to eq(true)
      expect(det["witness_phases"].include?(3)).to eq(true)
      expect(det["witness_phases"].include?(5)).to eq(true)

  context "Clue / Sudoku bitmask truth-table pruning and cross-arm clause sharing" ->
    it "projects forced units and pairwise Clue exclusions and shares them across arms via the ring" ->
      # Cluster {1, 2, 3}:
      # Clauses:
      #   (1 v 2 v 3)
      #   (1 v 2 v -3)
      #   (1 v -2 v 3)
      #   (1 v -2 v -3)  -> forces unit 1 = true!
      #   (-1 v -2 v -3) -> with 1 = true, forces Clue pairwise exclusion (-2 v -3)!
      cnf = [
        "p cnf 3 5",
        "1 2 3 0",
        "1 2 -3 0",
        "1 -2 3 0",
        "1 -2 -3 0",
        "-1 -2 -3 0"
      ].join("\n") + "\n"
      f = spec_flat_formula(cnf)
      tt = wassat_truth_table_prune(3, f)
      expect(tt["unsat"]).to eq(false)
      expect(tt["units"].include?(1)).to eq(true)
      expect(tt["binaries"].include?([-3, -2])).to eq(true)

      # Verify that wassat_apply_structural_pruning exports to the shared ring
      # and a peer arm imports the pruned clauses at level zero
      prune_info = wassat_structural_prune(3, f)
      ring = i64[8 + 64 * 27]
      s0 = Wassat.new(3, [[1, 2, 3]], WASSAT_PROOF_NONE, 0)
      s1 = Wassat.new(3, [[1, 2, 3]], WASSAT_PROOF_NONE, 0)
      s0.enable_sharing(ring, 64, 24, 0, true)
      s1.enable_sharing(ring, 64, 24, 1, true)
      rc = wassat_apply_structural_pruning(s0, prune_info, 1, true)
      expect(rc >= 0).to eq(true)
      expect(s1.share_import).to eq(0)
      expect(s1.value(1)).to eq(1)

  context "Branch memory (conflict-free @bphase, decision spine, and culprit tracking)" ->
    it "captures the conflict-free decision spine and bottom-conflict culprits before backjump" ->
      # PHP(4,3) forces multiple deep conflict-free descents and backjumps
      clauses = [
        [1, 2, 3], [4, 5, 6], [7, 8, 9], [10, 11, 12],
        [-1, -4], [-1, -7], [-1, -10], [-4, -7], [-4, -10], [-7, -10],
        [-2, -5], [-2, -8], [-2, -11], [-5, -8], [-5, -11], [-8, -11],
        [-3, -6], [-3, -9], [-3, -12], [-6, -9], [-6, -12], [-9, -12]
      ]
      s = Wassat.new(12, clauses, WASSAT_PROOF_NONE, 0)
      res = s.solve_budget(2)
      expect(s.best_spine_length > 0).to eq(true)
      expect(s.culprit_count > 0).to eq(true)
      full = s.solve_budget(0)
      expect(full["status"]).to eq(-1)

spec_summary
