use spec
use ../lib/solver
use ../lib/preprocess

+ FlatWatchFixture < Wassat
  -> watch_snapshot
    nlits = 2 * @nvars + 4
    binary = []
    long = []
    (0...nlits).each -> (li)
      bd = li << 1
      wd = li << 2
      bs = @bldir[bd]
      ws = @wsdir[wd]
      bins = []
      longs = []
      (0...@bldir[bd + 1]).each -> (i) bins.push(@bl_pool[bs + i])
      (0...@wsdir[wd + 1]).each -> (i) longs.push(@wpool[ws + i])
      binary.push([bs, @bldir[@bldir.size - 1 - li], bins])
      long.push([ws, @wsdir[wd + 2], @wsdir[wd + 3], longs])
    [binary, long, @bl_state[0], @wp_state[0]]

  -> retire_watched_pair
    @alive[1] = 0
    @alive[2] = 0

  -> rebuilt_entries
    @wp_state[4]

describe "Flat watch initialization" ->
  it "matches an independent repack of live mixed, repeated and signed watches" ->
    formula = wassat_parse_cnf_test_stub("p cnf 6 9\n1 2 0\n-2 -2 0\n1 3 2 0\n-3 -3 4 0\n-5 0\n0\n4 2 0\n-4 3 6 0\n5 4 6 0\n")
    ["flat_lits", "flat_offs", "flat_lens"].each -> (key)
      values = formula[key]
      raw = i64[values.size]
      (0...values.size).each -> (i) raw[i] = values[i]
      formula[key] = raw
    art = wassat_raw_artifact(formula, 6)
    # A preprocessor can leave dead rows in the source mirrors.
    alive = i64[9]
    gids = i64[9]
    (0...9).each -> (i)
      alive[i] = 1
      gids[i] = i + 1
    alive[6] = 0
    alive[7] = 0
    art["fsynth"] = false
    art["raw"] = false
    art["falive"] = alive
    art["fpgid"] = gids
    art["ftaut"] = i64[9]
    s = FlatWatchFixture.new(6, [], WASSAT_PROOF_NONE, 0, true)
    s.load_flat(art, true)
    initial = s.watch_snapshot
    expect(s.rebuilt_entries).to eq(6)
    # The duplicate negative binary occupies two slots on the same list.
    expect(initial[0][5][2]).to eq([(1 << 32) | 5, (1 << 32) | 5])
    expect(initial[1][7][3].size).to eq(2)
    s.rebuild_watches
    s.rebuild_binaries
    expect(s.watch_snapshot).to eq(initial)
    expect(s.rebuilt_entries).to eq(12)
    s.retire_watched_pair
    s.rebuild_watch_pools
    pruned = s.watch_snapshot
    expect(pruned[0][5][2].empty?).to eq(true)
    expect(s.rebuilt_entries).to eq(16)
    s.rebuild_watches
    s.rebuild_binaries
    expect(s.watch_snapshot).to eq(pruned)

  it "groups empty binary slots and uses their spares on the next insertion" ->
    s = FlatWatchFixture.new(4, [[1, 2]], WASSAT_PROOF_NONE, 0)
    s.rebuild_binaries
    before = s.watch_snapshot
    binary = before[0]
    empty_count = binary.size - 2
    binary.each -> (list)
      if list[2].empty?
        expect(list[0] < empty_count).to eq(true)
        expect(list[1]).to eq(1)
      else
        expect(list[0] >= empty_count).to eq(true)
    s.add_input_clause([-3, 4])
    s.add_input_clause([1, -2])
    after = s.watch_snapshot
    expect(after[2]).to eq(before[2])
    expect(after[0][7][2]).to eq([(1 << 32) | 8])
    expect(after[0][8][2]).to eq([(1 << 32) | 7])
    expect(after[0][2][2]).to eq([4, (2 << 32) | 5])
    expect(after[0][5][2]).to eq([(2 << 32) | 2])

spec_summary
