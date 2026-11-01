use spec
use ../lib/klieber_local

-> klieber_test_search(stop, deadline, cap, impossible)
  val = i64[9]
  ga = i64[9]; gb = i64[9]; gna = i64[9]; gnb = i64[9]; pol = i64[9]
  ga[7] = 1; gb[7] = 2
  targets = i64[2]
  targets[0] = 7; targets[1] = impossible ? -7 : 7
  meta = i64[6]
  wassat_klieber_local_search(val, ga, gna, gb, gnb, pol, targets, meta,
    6, 8, 2, stop, deadline, cap)
  meta

describe "Bit-parallel circuit kernel accounting and stopping" ->
  it "counts completed batches and gate work on a hit" ->
    m = klieber_test_search(i64[2], 0, 10, false)
    expect(m[0]).to eq(1)
    expect(m[2]).to eq(1)
    expect(m[3]).to eq(1)
    expect(m[4]).to eq(2)
    expect(m[5]).to eq(0)
    expect((m[1] & 3)).to eq(3)

  it "returns only a miss when the work cap is exhausted" ->
    m = klieber_test_search(i64[2], 0, 2, true)
    expect(m[0]).to eq(0)
    expect(m[2]).to eq(2)
    expect(m[3]).to eq(2)
    expect(m[4]).to eq(1)
    expect(m[5]).to eq(3)
    m = klieber_test_search(i64[2], 0, 0, true)
    expect(m[2]).to eq(0)

  it "honors prior cancellation and expired deadlines before evaluating gates" ->
    stop = i64[2]
    wassat_stop_cancel(stop)
    m = klieber_test_search(stop, 0, 10, false)
    expect(m[5]).to eq(1)
    expect(m[2]).to eq(0)
    m = klieber_test_search(i64[2], clock_ms() - 1, 10, false)
    expect(m[5]).to eq(2)
    expect(m[3]).to eq(0)

spec_summary
