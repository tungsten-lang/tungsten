use spec
use ../lib/policy

describe "Wassat physical-memory race planning" ->
  it "admits known-safe reservations above the former fixed ceiling" ->
    f = { "nvars": 100000, "flat_ncl": 200000, "flat_nlits": 600000 }
    # One small solver plus a three-GiB specialist fits easily on 128 GiB.
    expect(wassat_race_memory_fits_for_memory?(f, 1, 0, 0, 3221225472, 137438953472)).to eq(true)
    # The SAME request is declined on an eight-GiB host.
    expect(wassat_race_memory_fits_for_memory?(f, 1, 0, 0, 3221225472, 8589934592)).to eq(false)

  it "charges every resident solver, walker and preprocessor" ->
    f = { "nvars": 100000, "flat_ncl": 200000, "flat_nlits": 600000 }
    expect(wassat_race_memory_fits_for_memory?(f, 1, 1, 1, 0, 2147483648)).to eq(true)
    expect(wassat_race_memory_fits_for_memory?(f, 20, 1, 1, 0, 2147483648)).to eq(false)
    expect(wassat_race_memory_fits_for_memory?(f, 1, 40, 1, 0, 2147483648)).to eq(false)
    expect(wassat_race_memory_fits_for_memory?(f, 1, 1, 20, 0, 2147483648)).to eq(false)

  it "declines unknown capacity and never gives a zero-capacity host a budget" ->
    f = { "nvars": 100000, "flat_ncl": 200000, "flat_nlits": 600000 }
    expect(wassat_race_memory_fits_for_memory?(f, 0, 0, 0, 0, 0)).to eq(false)
    expect(wassat_race_memory_budget_bytes(0)).to eq(0)
    expect(wassat_race_memory_budget_bytes(-1)).to eq(0)

spec_summary
