use spec
use ../lib/wassat

# Three mandatory choices into two columns. Each choice requires a room,
# and each room conditionally forces a resource. No direct choice/room
# exclusions exist; all contradictions must use the unit and implication.
-> capacity_fixture(missing = "", reverse = false)
  rows = [[1, 2], [3, 4], [5, 6]]
  rows.push([31]) unless missing == "unit"
  x = 1
  while x <= 6
    r = 7 + 2 * (x - 1)
    rows.push([-x, r, r + 1]) unless missing == "room" && x == 1
    side = 0
    while side < 2
      t = 19 + 2 * (x - 1) + side
      unless missing == "implication" && x == 1 && side == 0
        rows.push([-x, -(r + side), -31, t])
      side += 1
    x += 1
  a = 0
  while a < 3
    b = a + 1
    while b < 3
      col = 0
      while col < 2
        i = 0
        while i < 2
          j = 0
          while j < 2
            unless (missing == "column" && col == 1) || (missing == "binary" && a == 0 && b == 1 && col == 0 && i == 0 && j == 0)
              rows.push([-(19 + 2 * (2 * a + col) + i), -(19 + 2 * (2 * b + col) + j)])
            j += 1
          i += 1
        col += 1
      b += 1
    a += 1
  rows.push([1, 1]) if missing == "duplicate"
  count = 0
  rows.each -> (row) count += row.size
  lits = i64[count]; offs = i64[rows.size]; lens = i64[rows.size]
  ci = 0; at = 0
  rows.each -> (row)
    row = row.reverse if reverse
    offs[ci] = at; lens[ci] = row.size
    row.each -> (lit)
      lits[at] = lit
      at += 1
    ci += 1
  { "nvars": 31, "flat_ncl": rows.size, "flat_nlits": count,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }


-> capacity_test_run(formula, cancel = false)
  p = { "meta": i64[24], "witness": i32[65], "width": 2, "scratch": 0 }
  stop = i64[4]
  wassat_stop_cancel(stop) if cancel
  res = i64[formula["nvars"] + 8]
  status = wassat_capacity_search(formula, p, stop, res, 0)
  { "status": status, "plan": p, "res": res, "stop": stop }

describe "Verified capacity clique" ->
  it "uses unit-guarded resource implications across every column" ->
    r = capacity_test_run(capacity_fixture)
    expect(r["status"]).to eq(-1)
    expect(r["plan"]["meta"][4]).to eq(12)
    expect(r["plan"]["meta"][8]).to eq(3)
    expect(wassat_stop_status(r["stop"])).to eq(-1)

  it "does not depend on literal order in the source clauses" ->
    expect(capacity_test_run(capacity_fixture("", true))["status"]).to eq(-1)

  it "declines when any required original premise is absent" ->
    ["unit", "room", "implication", "column", "binary"].each -> (missing)
      expect(capacity_test_run(capacity_fixture(missing))["status"]).to eq(0)

  it "rejects repeated domain literals and overlapping domains" ->
    expect(capacity_test_run(capacity_fixture("duplicate"))["status"]).to eq(0)

  it "honors cancellation before decode without publishing a verdict" ->
    r = capacity_test_run(capacity_fixture, true)
    expect(r["status"]).to eq(0)
    expect(r["res"][0]).to eq(0)
    expect(r["plan"]["meta"][10]).to eq(2)

  it "honors an expired deadline and counts polls" ->
    m = i64[24]
    m[11] = clock_ms() - 1
    expect(wassat_capacity_poll(m, i64[4])).to eq(1)
    expect(m[9]).to eq(1)

spec_summary
