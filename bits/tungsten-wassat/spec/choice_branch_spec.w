# Disjoint long clauses guide variable selection. CDCL owns the phase,
# remaining assignments, learned clauses and verdict.
use spec
use ../lib/solver

+ ChoiceBranchCheck < Wassat
  -> choose_now
    return 0 if @choice_rows == nil
    wassat_choice_variable(@choice_rows, @lassign)

describe("disjoint choice branching") ->
  it("picks from the tightest open row and skips satisfied rows") ->
    rows = i32[10]
    [4, 2, 4, 6, 8, 3, 11, 12, 14, 0].each_with_index -> (x, i)
      rows[i] = x
    values = i8[16]
    expect(wassat_choice_variable(rows, values)).to eq(5)
    values[2] = -1
    values[4] = -1
    expect(wassat_choice_variable(rows, values)).to eq(3)
    values[11] = 1
    values[6] = 1
    expect(wassat_choice_variable(rows, values)).to eq(0)

  it("uses signed choice rows and falls back when an input adds a long clause") ->
    cs = []
    (0...6).each -> (i)
      first = 1 + i * 4
      cs.push([0 - first, first + 1, first + 2, first + 3])
    (0...100).each -> (i)
      cs.push([1, -2])
    s = ChoiceBranchCheck.new(24, cs, WASSAT_PROOF_NONE, 0)
    expect(s.choose_now).to eq(1)
    ticks = s.unknown_result["ticks"]
    expect(s.pick_branch_rollout).to eq(1)
    expect(s.unknown_result["ticks"]).to eq(ticks)
    s.add_input_clause([2, 6, 10])
    expect(s.choose_now).to eq(0)
    expect(s.solve_assuming([2, 6])["sat"]).to eq(true)
    cs[1] = [-1, 6, 7, 8]
    overlap = ChoiceBranchCheck.new(24, cs, WASSAT_PROOF_NONE, 0)
    expect(overlap.choose_now).to eq(0)

spec_summary
