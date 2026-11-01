use spec
use ../lib/adder_conservation

# These records exercise the counted-token kernel. Original Boolean gate
# premises are covered by adder_conservation_spec and the caller's checks.
-> reduction_op(ops, at, side, a, b, c, sum, carry)
  at *= 7
  ops[at] = side
  ops[at + 1] = c == 0 ? 2 : 3
  ops[at + 2] = a
  ops[at + 3] = b
  ops[at + 4] = c
  ops[at + 5] = sum
  ops[at + 6] = carry

describe "Native counted adder reduction" ->
  it "preserves ordered passes and applies each identity only once" ->
    ops = i32[21]
    reduction_op(ops, 0, 0, 4, 5, 0, 6, 7)
    reduction_op(ops, 1, 0, 2, 3, 0, 4, 5)
    reduction_op(ops, 2, 0, 6, 7, 0, 8, 9)
    counts = i32[131072]
    counts[32770] = 1
    counts[32771] = 1
    used = i8[3]
    meta = i64[15]
    expect(wassat_adder_reduce(ops, 3, used, counts, meta, i64[1], 0)).to eq(1)
    expect(meta[6]).to eq(3)
    expect(meta[13]).to eq(3)
    expect(meta[14]).to eq(5)
    i = 2
    while i <= 9
      expect(counts[32768 + i]).to eq(i >= 8 ? 1 : 0)
      i += 1
    expect(used[0] + used[1] + used[2]).to eq(3)

  it "requires every occurrence of a repeated input" ->
    ops = i32[7]
    reduction_op(ops, 0, 0, 2, 2, 2, 3, 4)
    counts = i32[131072]
    counts[32770] = 2
    meta = i64[15]
    used = i8[1]
    expect(wassat_adder_reduce(ops, 1, used, counts, meta, i64[1], 0)).to eq(1)
    expect(meta[6]).to eq(0)
    expect(counts[32770]).to eq(2)
    counts[32770] = 3
    expect(wassat_adder_reduce(ops, 1, used, counts, meta, i64[1], 0)).to eq(1)
    expect(counts[32770]).to eq(0)
    expect(counts[32771]).to eq(1)
    expect(counts[32772]).to eq(1)

  it "keeps both outputs when they collide with existing tokens" ->
    ops = i32[7]
    reduction_op(ops, 0, 0, 2, 3, 0, 4, 4)
    counts = i32[131072]
    counts[32770] = 1
    counts[32771] = 1
    counts[32772] = 2
    expect(wassat_adder_reduce(ops, 1, i8[1], counts, i64[15], i64[1], 0)).to eq(1)
    expect(counts[32772]).to eq(4)
    expect(counts[32770] + counts[32771]).to eq(0)

  it "honors excluded operations and separates signed component tokens" ->
    ops = i32[14]
    reduction_op(ops, 0, 0, 2, -3, 4, -5, 6)
    reduction_op(ops, 1, 1, 2, -3, 4, -5, 6)
    counts = i32[131072]
    used = i8[2]
    used[0] = 2
    side = 0
    while side < 2
      base = side * 65536 + 32768
      counts[base + 2] = 1
      counts[base - 3] = 1
      counts[base + 4] = 1
      side += 1
    meta = i64[15]
    expect(wassat_adder_reduce(ops, 2, used, counts, meta, i64[1], 0)).to eq(1)
    expect(meta[6]).to eq(1)
    expect(used[0]).to eq(2)
    expect(counts[32770] + counts[32765] + counts[32772]).to eq(3)
    expect(counts[98306] + counts[98301] + counts[98308]).to eq(0)
    expect(counts[98299]).to eq(1)
    expect(counts[98310]).to eq(1)

  it "stops before mutation on prior cancellation or deadline" ->
    ops = i32[7]
    reduction_op(ops, 0, 0, 2, 3, 0, 4, 5)
    counts = i32[131072]
    counts[32770] = 1
    counts[32771] = 1
    meta = i64[15]
    stop = i64[1]
    wassat_stop_cancel(stop)
    expect(wassat_adder_reduce(ops, 1, i8[1], counts, meta, stop, 0)).to eq(0)
    expect(meta[8]).to eq(1)
    meta = i64[15]
    expect(wassat_adder_reduce(ops, 1, i8[1], counts, meta, i64[1], clock_ms() - 1)).to eq(0)
    expect(meta[8]).to eq(2)
    expect(counts[32770] + counts[32771]).to eq(2)
    expect(counts[32772] + counts[32773]).to eq(0)

  it "honors the shared work budget and an existing failure" ->
    ops = i32[7]
    reduction_op(ops, 0, 0, 2, 3, 0, 4, 5)
    counts = i32[131072]
    counts[32770] = 1
    counts[32771] = 1
    meta = i64[15]
    meta[7] = 2000000
    expect(wassat_adder_reduce(ops, 1, i8[1], counts, meta, i64[1], 0)).to eq(0)
    expect(meta[8]).to eq(3)
    expect(meta[6]).to eq(0)
    meta[7] = 0
    expect(wassat_adder_reduce(ops, 1, i8[1], counts, meta, i64[1], 0)).to eq(0)
    expect(meta[7]).to eq(0)
    expect(counts[32770] + counts[32771]).to eq(2)

spec_summary
