use spec
use ../lib/solver

+ TernaryMembershipAudit < Wassat
  -> strengthened_pairs
    old = @ncl
    count = self.extract_binaries
    pairs = []
    ci = old
    while ci < @ncl
      off = @cmeta[2 * ci]
      pairs.push([@arena[off], @arena[off + 1]])
      ci += 1
    [count, pairs]

-> check_ternary_membership(pivot, noise, missing, existing)
  ls = [-1, 2, -3]
  a = ls[pivot]
  rest = []
  ls.each_with_index -> (l, i)
    rest.push(l) if i != pivot
  cs = [ls, ls, ls, ls]
  cs.push([-a, rest[0]]) unless missing
  cs.push([rest[0], rest[1]]) if existing
  i = 0
  while i < noise
    cs.push([-a, i + 7])
    i += 1
  solver = TernaryMembershipAudit.new(noise + 7, cs, WASSAT_PROOF_NONE)
  expected = missing || existing ? [0, []] : [1, [rest]]
  expect(solver.strengthened_pairs).to eq(expected)

describe "Ternary binary membership" ->
  it "preserves implication priority, signs and duplicate suppression" ->
    [0, 1, 2].each -> (pivot)
      check_ternary_membership(pivot, 0, false, false)

  it "checks high-degree opposite endpoints and absent premises" ->
    [0, 1, 2].each -> (pivot)
      check_ternary_membership(pivot, 80, false, false)
      check_ternary_membership(pivot, 80, true, false)

  it "does not emit binary clauses already in either adjacency" ->
    [0, 1, 2].each -> (pivot)
      check_ternary_membership(pivot, 80, false, true)


describe "Exact either-binary adjacency queries" ->
  it "matches an independent edge oracle with bounded reads" ->
    seed = 0
    while seed < 12
      bd = i64[80]; pool = i64[2048]; state = i64[4]; state[1] = 2048
      edges = []
      a = 2
      while a < 18
        b = a
        while b < 18
          if (a * 17 + b * 31 + seed) % 11 < 3
            edges.push([a, b])
            wassat_bl_add(bd, pool, state, a, 2147483647, b)
            wassat_bl_add(bd, pool, state, b, 2147483647, a)
          b += 1
        a += 1
      q = 0
      while q < 32
        a = 2 + (q * 7 + seed) % 16
        b = 2 + (q * 3 + seed * 2) % 16
        c = q % 4 == 0 ? b : 2 + (q * 5 + seed * 3) % 16
        expected = false
        edges.each -> (edge)
          expected = true if (edge[0] == a && (edge[1] == b || edge[1] == c)) || (edge[1] == a && (edge[0] == b || edge[0] == c))
        code = wassat_binary_either(bd, pool, a, b, c)
        expect((code & 1) == 1).to eq(expected)
        bound = bd[4 * a + 1]
        opposite = bd[4 * b + 1] + bd[4 * c + 1]
        bound = opposite if opposite < bound
        expect((code >> 1) <= bound).to eq(true)
        q += 1
      seed += 1

spec_summary
