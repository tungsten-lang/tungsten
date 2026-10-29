use spec
use ../lib/sls

-> sls_occ_at(offsets, clauses, literal)
  result = []
  i = offsets[literal]
  while i < offsets[literal + 1]
    result.push(clauses[i])
    i += 1
  result

describe "Contiguous SLS occurrences" ->
  it "preserves reverse-insertion visitation order and resets empty ranges" ->
    literals = i64[7]; offsets = i64[3]; lengths = i64[3]
    input = [1, -2, 3, 1, 2, -2, -3]
    i = 0
    while i < 7
      literals[i] = input[i]
      i += 1
    offsets[0] = 0; lengths[0] = 3
    offsets[1] = 3; lengths[1] = 2
    offsets[2] = 5; lengths[2] = 2
    starts = i64[10]; clauses = i64[7]
    wassat_sls_build_occ(literals, offsets, lengths, starts, clauses, 3, 3)
    expect(sls_occ_at(starts, clauses, 2)).to eq([1, 0])
    expect(sls_occ_at(starts, clauses, 3)).to eq([])
    expect(sls_occ_at(starts, clauses, 4)).to eq([1])
    expect(sls_occ_at(starts, clauses, 5)).to eq([2, 0])
    expect(sls_occ_at(starts, clauses, 6)).to eq([0])
    expect(sls_occ_at(starts, clauses, 7)).to eq([2])
    expect(starts[8]).to eq(7)
    wassat_sls_build_occ(literals, offsets, lengths, starts, clauses, 0, 3)
    expect(sls_occ_at(starts, clauses, 2)).to eq([])
    expect(starts[8]).to eq(0)
  it "builds the same ranges after root filtering, deduplication and tautology removal" ->
    arena = i64[10]; meta = i64[8]; alive = i64[4]; lbd = i64[4]; assign = i8[4]
    input = [1, 2, -1, 3, 2, -2, 3, 2, 2, 3]
    i = 0
    while i < 10
      arena[i] = input[i]
      i += 1
    meta[0] = 0; meta[1] = 2; meta[2] = 2; meta[3] = 2
    meta[4] = 4; meta[5] = 3; meta[6] = 7; meta[7] = 3
    i = 0
    while i < 4
      alive[i] = 1
      i += 1
    assign[1] = 1
    literals = i64[12]; offsets = i64[6]; lengths = i64[6]
    starts = i64[10]; clauses = i64[12]; stamp = i64[10]; pm = i64[8]
    pm[0] = 4; pm[1] = 3; pm[6] = 4; pm[7] = 10
    wassat_sls_from_arena(arena, meta, alive, lbd, assign,
      literals, offsets, lengths, starts, clauses, stamp, pm)
    expect(pm[2]).to eq(2)
    expect(pm[3]).to eq(3)
    expect(literals[0]).to eq(3)
    expect(literals[1]).to eq(2)
    expect(literals[2]).to eq(3)
    expect(sls_occ_at(starts, clauses, 4)).to eq([1])
    expect(sls_occ_at(starts, clauses, 6)).to eq([1, 0])

spec_summary
