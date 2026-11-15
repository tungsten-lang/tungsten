# The Kissat search profile (Wassat#enable_kissat_search): its schedule
# kernels, its clause-database reduction, the conflict-analysing vivifier,
# and the verdicts of whole searches run under it.

use spec
use ../lib/solver

+ KissatSearchFixture < Wassat
  ro :nlearned, :vivified, :dlevel, :tsize

  -> live(ci)
    @alive[ci] == 1

  -> clause(ci)
    out = []
    st = @cmeta[2 * ci]
    n = @cmeta[2 * ci + 1]
    i = 0
    while i < n
      out.push(@arena[st + i])
      i += 1
    out.sort.join(" ")

  -> live_clauses
    out = []
    ci = 0
    while ci < @ncl
      out.push(self.clause(ci)) if @alive[ci] == 1
      ci += 1
    out

  -> mark_learned(ci, glue)
    @clbd[ci] = glue
    @cused[ci] = @conflicts + 1
    @nlearned += 1
    0

  -> vivify(budget)
    self.vivify_strong(budget)

  -> seen_clear?
    v = 1
    clear = true
    while v <= @nvars
      clear = false if @seen[v] != 0
      v += 1
    clear

  -> saved_phase(v)
    @phase[v]

# A deterministic 3-CNF over `nv` variables: `nc` clauses of three distinct
# variables, signs and choices from a 31-bit linear congruential sequence.
-> ks_random_3cnf(nv, nc, seed)
  x = seed
  clauses = []
  while clauses.size < nc
    lits = []
    while lits.size < 3
      x = (x * 1103515245 + 12345) % 2147483648
      v = (x / 65536) % nv + 1
      x = (x * 1103515245 + 12345) % 2147483648
      sign = (x / 65536) % 2 == 0 ? 1 : -1
      dup = false
      lits.each -> (l)
        dup = true if l == v || l == 0 - v
      lits.push(sign * v) unless dup
    clauses.push(lits)
  clauses

-> ks_satisfies?(clauses, model)
  ok = true
  clauses.each -> (c)
    hit = false
    c.each -> (l)
      v = l < 0 ? 0 - l : l
      hit = true if model[v - 1] == l
    ok = false unless hit
  ok

# Clause tables for the reduction kernel: one clause per entry, with the
# given length, glue (0 = irredundant) and last-use stamp.
-> ks_reduce_tables(lens, glues, used)
  n = lens.size
  cm = i64[2 * n]; alive = i8[n]; lbd = i64[n]; us = i64[n]
  i = 0
  while i < n
    cm[2 * i + 1] = lens[i]
    alive[i] = 1
    lbd[i] = glues[i]
    us[i] = used[i]
    i += 1
  { "cm": cm, "alive": alive, "lbd": lbd, "used": us }

# Pigeonhole PHP(p, h) as clause lists: every pigeon in a hole, no hole twice.
-> ks_php(p, h)
  clauses = []
  i = 0
  while i < p
    row = []
    j = 0
    while j < h
      row.push(i * h + j + 1)
      j += 1
    clauses.push(row)
    i += 1
  j = 0
  while j < h
    a = 0
    while a < p
      b = a + 1
      while b < p
        clauses.push([0 - (a * h + j + 1), 0 - (b * h + j + 1)])
        b += 1
      a += 1
    j += 1
  clauses

describe "Kissat schedule kernels" ->
  it "spaces mode switches by n * log10(n + 9)^4 thousand conflicts" ->
    a = wassat_kmode_interval(1)
    b = wassat_kmode_interval(2)
    c = wassat_kmode_interval(10)
    expect(a >= 990 && a <= 1000).to eq(true)
    expect(b >= 2330 && b <= 2353).to eq(true)
    expect(c >= 26600 && c <= 26740).to eq(true)
    n = 1
    last = 0
    while n <= 60
      v = wassat_kmode_interval(n)
      expect(v > last).to eq(true)
      last = v
      n += 1

  it "waits one conflict between focused restarts, more by decimal orders" ->
    expect(wassat_krestart_delay(0)).to eq(1)
    expect(wassat_krestart_delay(90)).to eq(1)
    expect(wassat_krestart_delay(91)).to eq(2)
    expect(wassat_krestart_delay(990)).to eq(2)
    expect(wassat_krestart_delay(991)).to eq(3)

  it "spaces reductions by 1000 * sqrt(n) conflicts" ->
    expect(wassat_kreduce_interval(1)).to eq(1000)
    expect(wassat_kreduce_interval(2)).to eq(1414)
    expect(wassat_kreduce_interval(4)).to eq(2000)
    expect(wassat_kreduce_interval(100)).to eq(10000)

  it "corrects the bias of an average started at zero" ->
    kst = i64[16]
    wassat_kema_init(kst)
    wassat_kema_conflict(kst, 5, 3, 1)
    # one sample: both averages read that sample, not sample / window
    expect(kst[4] > 320000 && kst[4] < 335000).to eq(true)
    expect(kst[5] > 320000 && kst[5] < 335000).to eq(true)
    expect(wassat_krestart_hot(kst, 1)).to eq(0)
    i = 0
    while i < 2000
      wassat_kema_conflict(kst, 5, 3 + i, 1)
      i += 1
    # a steady glue of 5: both averages read 5, within a part in a hundred
    expect(kst[4] > 324000 && kst[4] < 331000).to eq(true)
    expect(kst[5] > 324000 && kst[5] < 331000).to eq(true)
    expect(wassat_krestart_hot(kst, 5000)).to eq(0)
    i = 0
    while i < 40
      wassat_kema_conflict(kst, 9, 2003 + i, 1)
      i += 1
    # the fast average follows the jump, the slow one barely moves
    expect(kst[5] < 335000).to eq(true)
    expect(wassat_krestart_hot(kst, 5000)).to eq(1)
    kst[6] = 6000
    expect(wassat_krestart_hot(kst, 5000)).to eq(0)

  it "leaves the glue averages alone in stable mode" ->
    kst = i64[16]
    wassat_kema_init(kst)
    wassat_kema_conflict(kst, 5, 3, 1)
    fast = kst[4]
    wassat_kema_conflict(kst, 50, 6, 0)
    expect(kst[4]).to eq(fast)

  it "sorts variables by ascending key" ->
    a = i64[6]
    key = i64[8]
    a[0] = 3; a[1] = 1; a[2] = 2; a[3] = 5; a[4] = 4
    key[1] = 30; key[2] = 10; key[3] = 20; key[4] = 5; key[5] = 40
    wassat_sort_by_key(a, key, 5)
    expect(a[0]).to eq(4)
    expect(a[1]).to eq(2)
    expect(a[2]).to eq(3)
    expect(a[3]).to eq(1)
    expect(a[4]).to eq(5)

  it "puts the asserting literal and the highest remaining level first" ->
    lb = i64[5]; ob = i64[5]; lvl = i64[8]
    lb[0] = -7; lb[1] = 2; lb[2] = -3; lb[3] = 4
    lvl[7] = 9; lvl[2] = 1; lvl[3] = 6; lvl[4] = 4
    wassat_watch_order(lb, ob, lvl, 4)
    expect(ob[0]).to eq(-7)
    expect(ob[1]).to eq(-3)
    expect(ob[2]).to eq(2)
    expect(ob[3]).to eq(4)

  it "finds the deepest decision prefix a restart can keep" ->
    tr = i32[8]; tlim = i32[4]; key = i64[8]
    tr[0] = 1; tr[1] = -2; tr[2] = 3
    tlim[0] = 0; tlim[1] = 1; tlim[2] = 2
    key[1] = 50; key[2] = 40; key[3] = 10
    expect(wassat_reuse_trail_level(tr, tlim, key, 3, 30)).to eq(2)
    expect(wassat_reuse_trail_level(tr, tlim, key, 3, 5)).to eq(3)
    expect(wassat_reuse_trail_level(tr, tlim, key, 3, 60)).to eq(0)

describe "Kissat clause-database reduction" ->
  it "keeps used, low-glue and short clauses and drops the longest of the rest" ->
    t = ks_reduce_tables([20, 5, 10, 10, 30, 20, 20, 10, 10, 8],
                         [0, 9, 2, 5, 9, 9, 4, 7, 3, 3],
                         [0, 0, 0, 60, 0, 0, 0, 0, 0, 0])
    cm = t["cm"] ## i64[]
    alive = t["alive"] ## i8[]
    lbd = t["lbd"] ## i64[]
    used = t["used"] ## i64[]
    hist = i64[1088]; tr = i32[4]; rsn = i32[4]; lvl = i64[4]
    left = wassat_kreduce_select(cm, alive, lbd, used, hist, 10, 50, tr, rsn, lvl, 0, 100)
    # candidates 4..7 hold 80 literals (8 and 9 have LBD 3); 70% is 56:
    # the 30, then both 20s
    expect(left).to eq(6)
    expect(alive[0]).to eq(1)
    expect(alive[1]).to eq(1)
    expect(alive[2]).to eq(1)
    expect(alive[3]).to eq(1)
    expect(alive[4]).to eq(0)
    expect(alive[5]).to eq(0)
    expect(alive[6]).to eq(0)
    expect(alive[7]).to eq(1)
    expect(alive[8]).to eq(1)
    expect(alive[9]).to eq(1)

  it "never drops the reason of an assignment above the root" ->
    t = ks_reduce_tables([20, 5, 10, 10, 30, 20, 20, 10, 10, 8],
                         [0, 9, 2, 5, 9, 9, 4, 7, 3, 3],
                         [0, 0, 0, 60, 0, 0, 0, 0, 0, 0])
    cm = t["cm"] ## i64[]
    alive = t["alive"] ## i8[]
    lbd = t["lbd"] ## i64[]
    used = t["used"] ## i64[]
    hist = i64[1088]; tr = i32[4]; rsn = i32[4]; lvl = i64[4]
    tr[0] = 1; tr[1] = -2
    rsn[1] = -1; lvl[1] = 1
    rsn[2] = 4; lvl[2] = 1
    # `last` equal to `now`: the mark must still read as newer
    left = wassat_kreduce_select(cm, alive, lbd, used, hist, 10, 100, tr, rsn, lvl, 2, 100)
    expect(alive[4]).to eq(1)
    # 60 literals of candidates (clauses 3, 5, 6, 7), 42 to go: both 20s,
    # then the 10 with the higher glue
    expect(alive[5]).to eq(0)
    expect(alive[6]).to eq(0)
    expect(alive[7]).to eq(0)
    expect(alive[3]).to eq(1)
    expect(left).to eq(6)
    expect(wassat_trail_reasons_alive(tr, rsn, lvl, alive, 2)).to eq(1)
    alive[4] = 0
    expect(wassat_trail_reasons_alive(tr, rsn, lvl, alive, 2)).to eq(0)
    lvl[2] = 0
    expect(wassat_trail_reasons_alive(tr, rsn, lvl, alive, 2)).to eq(1)

describe "Conflict-analysing vivification" ->
  it "drops a literal the other assumptions imply false" ->
    # not 1 and not 2 force not 3 through the second clause
    s = KissatSearchFixture.new(6, [[1, 2, 3, 4], [1, 2, -3], [5, 6]], 0, 0)
    s.enable_kissat_search
    s.vivify(100000)
    expect(s.dlevel).to eq(0)
    expect(s.seen_clear?).to eq(true)
    expect(s.live(0)).to eq(false)
    expect(s.live_clauses.include?("1 2 4")).to eq(true)

  it "cuts a clause down to the assumptions a conflict depends on" ->
    # not 1 forces 5 and 6, which the last clause forbids: the unit 1
    s = KissatSearchFixture.new(6, [[1, 2, 3, 4], [1, 5], [1, 6], [-5, -6]], 0, 0)
    s.enable_kissat_search
    s.vivify(100000)
    expect(s.dlevel).to eq(0)
    expect(s.seen_clear?).to eq(true)
    expect(s.live(0)).to eq(false)
    expect(s.value(1)).to eq(1)

  it "shortens a learned clause to the literal its neighbours imply" ->
    # not 1 forces 2 through the first clause: the learned (1 2 3) becomes (1 2)
    s = KissatSearchFixture.new(4, [[1, 2], [1, 2, 3], [3, 4]], 0, 0)
    s.enable_kissat_search
    s.mark_learned(1, 3)
    s.vivify(100000)
    expect(s.live(1)).to eq(false)
    expect(s.live(0)).to eq(true)
    expect(s.live(2)).to eq(true)
    expect(s.live_clauses.include?("1 2 3")).to eq(false)
    expect(s.vivified).to eq(1)

  it "restores the saved phases it propagated over" ->
    s = KissatSearchFixture.new(6, [[1, 2, 3, 4], [1, 2, -3], [5, 6]], 0, 0)
    s.enable_kissat_search
    before = []
    v = 1
    while v <= 6
      before.push(s.saved_phase(v))
      v += 1
    s.vivify(100000)
    v = 1
    while v <= 6
      expect(s.saved_phase(v)).to eq(before[v - 1])
      v += 1

describe "Search under the Kissat profile" ->
  it "refutes pigeonhole formulas" ->
    s = Wassat.new(42, ks_php(7, 6), 0, 0)
    s.enable_kissat_search
    r = s.solve
    expect(r["unsat"]).to eq(true)

  it "finds a model of a satisfiable pigeonhole formula" ->
    clauses = ks_php(6, 6)
    s = Wassat.new(36, clauses, 0, 0)
    s.enable_kissat_search
    r = s.solve
    expect(r["sat"]).to eq(true)
    expect(ks_satisfies?(clauses, r["model"])).to eq(true)

  it "agrees with the older schedule on random 3-CNF, with checked models" ->
    seed = 1
    sat = 0
    unsat = 0
    while seed <= 24
      clauses = ks_random_3cnf(60, 258, seed * 7919)
      a = Wassat.new(60, clauses, 0, 0)
      ra = a.solve
      b = Wassat.new(60, clauses, 0, 0)
      b.enable_kissat_search
      rb = b.solve
      expect(rb["complete"]).to eq(true)
      expect(rb["sat"]).to eq(ra["sat"])
      if rb["sat"]
        sat += 1
        expect(ks_satisfies?(clauses, rb["model"])).to eq(true)
      else
        unsat += 1
      seed += 1
    # the sample has to exercise both verdicts to mean anything
    expect(sat > 2).to eq(true)
    expect(unsat > 2).to eq(true)

  it "continues one search across budget slices" ->
    clauses = ks_php(8, 7)
    s = Wassat.new(56, clauses, 0, 0)
    s.enable_kissat_search
    r = s.solve_budget(200)
    slices = 1
    while r["status"] == 0 && slices < 2000
      r = s.solve_budget(200)
      slices += 1
    expect(r["unsat"]).to eq(true)
    expect(slices > 1).to eq(true)

spec_summary
