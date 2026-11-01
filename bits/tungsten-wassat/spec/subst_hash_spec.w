use spec
use ../lib/solver

-> hash_rewrite_fixture(clauses, nv, mappings = [], capacity = 1024, limit = 1024, learned = false)
  ncl = clauses.size
  total = ncl + 1
  clauses.each ->(c) total += c.size
  cm = i64[2 * ncl]
  alive = i8[ncl]
  ar = i64[total]
  clbd = i64[ncl]
  reprs = i64[2 * nv + 4]
  mark = i64[2 * nv + 4]
  ht = i64[capacity]
  units = i64[ncl + 2]
  st = i64[8]
  ci = 0
  pos = 1
  clauses.each ->(c)
    cm[2 * ci] = pos
    cm[2 * ci + 1] = c.size
    alive[ci] = 1
    ar[pos - 1] = (ci << 32) | c.size
    c.each ->(l)
      ar[pos] = l
      pos += 1
    pos += 1
    ci += 1
  clbd[0] = 5 if learned
  mappings.each ->(pair)
    a = pair[0]
    b = pair[1]
    ai = a > 0 ? 2 * a : 2 * (0 - a) + 1
    bi = b > 0 ? 2 * b : 2 * (0 - b) + 1
    reprs[ai] = bi
    reprs[ai ^ 1] = bi ^ 1
  wassat_subst_rewrite(cm, alive, ar, clbd, reprs, mark, ht, units, st, ncl, capacity - 1, limit)
  out = []
  ci = 0
  while ci < ncl
    if alive[ci] == 1
      c = []
      j = 0
      while j < cm[2 * ci + 1]
        c.push(ar[cm[2 * ci] + j])
        j += 1
      out.push(c)
    ci += 1
  { "clauses": out, "alive": alive, "lbd": clbd, "stats": st }

describe "Substitution duplicate-clause hashing" ->
  it "keeps equal-sum clauses distinct and recognizes permutations" ->
    r = hash_rewrite_fixture([[1, 4], [2, 3], [4, 1], [3, 2]], 4)
    expect(r["clauses"]).to eq([[1, 4], [2, 3]])
    expect(r["stats"][3]).to eq(2)
    expect(r["stats"][4]).to eq(4)

  it "preserves signed rewrites, tautology removal and exposed units" ->
    r = hash_rewrite_fixture([[2, 4], [4, 1], [2, 3], [2, 1]], 4, [[2, 1], [3, -1]])
    expect(r["clauses"]).to eq([[1, 4], [1]])
    expect(r["stats"][1]).to eq(1)
    expect(r["stats"][3]).to eq(2)

  it "promotes the first surviving learned duplicate to irredundant" ->
    r = hash_rewrite_fixture([[1, 2], [2, 1]], 2, [], 1024, 1024, true)
    expect(r["clauses"]).to eq([[1, 2]])
    expect(r["lbd"][0]).to eq(0)
    expect(r["alive"][1]).to eq(0)

  it "requires exact equality even when the table is full and probes are capped" ->
    r = hash_rewrite_fixture([[1, 2], [3, 4], [2, 1], [4, 3]], 4, [], 1, 1)
    expect(r["clauses"]).to eq([[1, 2], [3, 4], [4, 3]])
    expect(r["stats"][5]).to eq(3)
    expect(r["stats"][7]).to eq(1)

  it "avoids quadratic probing across many distinct equal-sum pairs" ->
    cs = []
    i = 1
    while i <= 96
      cs.push([i, 193 - i])
      i += 1
    r = hash_rewrite_fixture(cs, 192)
    expect(r["clauses"]).to eq(cs)
    expect(r["stats"][4]).to eq(96)
    expect(r["stats"][5] < 384).to eq(true)
    expect(r["stats"][7] < 16).to eq(true)

spec_summary
