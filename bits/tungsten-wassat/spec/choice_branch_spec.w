# Disjoint choice rows guide variable selection. Verified overlapping
# exactly-one rows also supply the selected literal’s decision phase.
use spec
use ../lib/solver

+ ChoiceBranchCheck < Wassat
  ro :first_decision

  -> start_with_positive_phase
    @phase[1] = 1

  -> enqueue(lit, reason)
    @first_decision = lit if reason == -1 && @first_decision == nil
    super(lit, reason)

  -> choice_polarity(v)
    return 0 if @choice_polarities == nil
    @choice_polarities[v]

  -> choose_now
    return 0 if @choice_rows == nil
    wassat_choice_variable(@choice_rows, @lassign)

# Two partitions of the same signed literals. The pair (-1, 3) appears
# together in only one row, so omitting its exclusion breaks exact-one.
-> overlapping_choices(complete)
  clauses = []
  (0...2).each -> (shift)
    (0...6).each -> (r)
      row = []
      (0...4).each -> (i)
        v = (4 * r + i + 2 * shift) % 24 + 1
        row.push(v == 1 ? -1 : v)
      clauses.push(row)
      (0...4).each -> (i)
        ((i + 1)...4).each -> (j)
          clauses.push([0 - row[i], 0 - row[j]]) if complete || row[i] != -1 || row[j] != 3
  (0...20).each -> (i)
    clauses.push([1, -2])
  clauses

describe("branching on choice clauses") ->
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

  it("can stop at two open choices while an unrestricted scan still finds a later singleton") ->
    rows = i32[9]
    [3, 2, 4, 6, 3, 8, 10, 12, 0].each_with_index -> (x, i)
      rows[i] = x
    values = i8[14]
    values[2] = -1
    values[8] = -1
    values[10] = -1
    expect(wassat_choice_variable(rows, values)).to eq(6)
    expect(wassat_choice_variable_until(rows, values, 2)).to eq(2)

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

  it("selects signed values for overlapping rows with complete binary exclusions") ->
    s = ChoiceBranchCheck.new(24, overlapping_choices(true), WASSAT_PROOF_NONE, 0)
    expect(s.choose_now).to eq(1)
    expect(s.choice_polarity(1)).to eq(-1)
    expect(s.choice_polarity(24)).to eq(1)
    s.start_with_positive_phase
    result = s.solve_assuming([])
    expect(s.first_decision).to eq(-1)
    expect(result["sat"]).to eq(true)
    expect(result["model"][0]).to eq(-1)
    s.add_input_clause([2, 8, 12])
    expect(s.choice_polarity(1)).to eq(0)
    expect(s.choose_now).to eq(0)

  it("requires a binary exclusion for every pair in each overlapping row") ->
    s = ChoiceBranchCheck.new(24, overlapping_choices(false), WASSAT_PROOF_NONE, 0)
    expect(s.choice_polarity(1)).to eq(0)
    expect(s.choose_now).to eq(0)

spec_summary
