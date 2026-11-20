use spec
use ../lib/solver

# The focused search must move the same variables in exactly the same order.
# The untouched suffix detects writes past the analyzed set.
-> check_conflict_sort(n, spare, pattern)
  vars = i64[n + 2]
  reference = i64[n + 2]
  stamps = i64[n + 1]
  work = i64[n]
  aux = i64[n + spare]
  (0...n).each -> (i)
    v = n - i
    vars[i] = v
    reference[i] = v
    case pattern
      when "one byte"
        stamps[v] = 2147483392 + (v % 256)
      when "skip middle byte"
        stamps[v] = 16777216 * (v % 64) + v
      when "four bytes"
        stamps[v] = (v * 1588635695) & 2147483647
      when "ties"
        stamps[v] = v % 17
      when "negative"
        stamps[v] = 0 - v
      when "wide"
        stamps[v] = 4294967296 + v
  vars[n] = 10001
  reference[n] = 10001
  vars[n + 1] = 10002
  reference[n + 1] = 10002
  wassat_sort_by_key(reference, stamps, n)
  wassat_sort_conflict_vars(vars, stamps, n, work, aux)
  i = 0 ## i64
  while i < vars.size
    return false if vars[i] != reference[i]
    i += 1
  true

describe "Conflict variable ordering" ->
  it "preserves recency order across the size and scratch cutoffs" ->
    [0, 1, 95, 96, 97, 255].each -> (n)
      [0, 255, 256, 257].each -> (spare)
        expect(check_conflict_sort(n, spare, "one byte")).to eq(true)

  it "preserves Shell order for multiple stamp bytes, ties and full-width timestamps" ->
    ["skip middle byte", "four bytes", "ties", "negative", "wide"].each -> (pattern)
      expect(check_conflict_sort(1025, 256, pattern)).to eq(true)

spec_summary
