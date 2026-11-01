use spec
use ../lib/wassat
use ../../tungsten-wrat/lib/wrat

+ StorageReuseProbe < WassatPreprocess
  -> prepare
    self.init_budget
    self.intake

  -> prepare_flat(parse)
    self.init_budget
    self.intake_flat(parse)

  -> sizes
    [@fasize, @osize, @facap, @ocap, @ncl]

  -> tighten
    @facap = @fasize
    @ocap = @osize

  -> logical_snapshot
    out = [@next_gid, @ncl, @ftsize, @fqhead, @stack.to_s, @wrat_lines.to_s, @drat_lines.to_s]
    ci = 0
    while ci < @ncl
      if @falive[ci] == 1
        out.push([ci, @fcl[ci], @ftaut[ci], @fsig[ci], @fpgid[ci], self.copy_clause_lits(ci)])
      ci += 1
    li = 0
    while li < 2 * @nvars + 2
      out.push([@ocount[li], self.live_occ(li)])
      li += 1
    v = 0
    while v <= @nvars
      out.push([@passign[v], @preason[v], @tpos[v], @gone[v], @replit[v]])
      v += 1
    out

# Publish after the last admission check, at entry to the indivisible repair.
+ CancelReuseProbe < StorageReuseProbe
  -> compact_live_storage
    z = wassat_stop_cancel(@stop_cell)
    super

-> reuse_check_sat(pre, text)
  art = pre.artifact
  f = wassat_parse_cnf(text)
  s = Wassat.new(f["nvars"], art["clauses"], WASSAT_PROOF_NONE, 0)
  r = s.solve_budget(0)
  expect(r["sat"]).to eq(true)
  model = wassat_reconstruct_model(art["stack"], r["model"], f["nvars"])
  expect(wassat_model_satisfies?(f, model)).to eq(true)

REUSE_GAPS = "p cnf 8 5\n1 2 0\n-1 3 0\n4 -4 0\n-5 6 6 0\n7 8 0\n"

describe "BVE live storage reuse" ->
  it "packs deletion gaps while preserving ordered live occurrences and reconstruction" ->
    f = wassat_parse_cnf(REUSE_GAPS)
    pre = StorageReuseProbe.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, nil)
    pre.prepare
    expect(pre.try_eliminate(1)).to eq(true)
    before = pre.logical_snapshot
    sizes = pre.sizes
    pre.compact_live_storage
    expect(pre.logical_snapshot).to eq(before)
    after = pre.sizes
    expect(after[0] < sizes[0]).to eq(true)
    expect(after[1] < sizes[1]).to eq(true)
    expect(after[2]).to eq(sizes[2])
    expect(after[3]).to eq(sizes[3])
    expect(after[4]).to eq(sizes[4])
    pre.compact_live_storage
    expect(pre.logical_snapshot).to eq(before)
    expect(pre.sizes).to eq(after)
    reuse_check_sat(pre, REUSE_GAPS)

  it "reclaims before committing a proposal that would grow both buffers" ->
    text = "p cnf 6 4\n1 2 0\n-1 3 0\n4 5 0\n-4 6 0\n"
    f = wassat_parse_cnf(text)
    pre = StorageReuseProbe.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, nil)
    pre.prepare
    pre.freeze(2)
    pre.freeze(3)
    pre.freeze(5)
    pre.freeze(6)
    expect(pre.try_eliminate(1)).to eq(true)
    pre.tighten
    capacity = pre.sizes
    pre.run_bve
    art = pre.artifact
    expect(art["stats"]["storage_compactions"]).to eq(1)
    expect(pre.sizes[2]).to eq(capacity[2])
    expect(pre.sizes[3]).to eq(capacity[3])
    reuse_check_sat(pre, text)

  it "does not reserve a whole output buffer for small accepted proposals" ->
    f = wassat_parse_cnf(REUSE_GAPS)
    pre = StorageReuseProbe.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, nil)
    pre.prepare
    pre.run_bve
    expect(pre.artifact["stats"]["storage_compactions"]).to eq(0)
    reuse_check_sat(pre, REUSE_GAPS)

  it "allows ordinary growth instead of repeatedly scanning for tiny gaps" ->
    text = "p cnf 9 6\n1 2 0\n-1 3 0\n4 5 0\n-4 6 0\n7 8 0\n-7 9 0\n"
    f = wassat_parse_cnf(text)
    pre = StorageReuseProbe.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, nil)
    pre.prepare
    expect(pre.try_eliminate(1)).to eq(true)
    pre.tighten
    expect(pre.try_eliminate(4)).to eq(true)
    pre.tighten
    capacity = pre.sizes
    expect(pre.try_eliminate(7)).to eq(true)
    expect(pre.artifact["stats"]["storage_compactions"]).to eq(1)
    expect(pre.sizes[2] > capacity[2]).to eq(true)
    reuse_check_sat(pre, text)

  it "discards an uncommitted proposal after cancellation and can resume safely" ->
    text = "p cnf 6 4\n1 2 0\n-1 3 0\n4 5 0\n-4 6 0\n"
    f = wassat_parse_cnf(text)
    pre = CancelReuseProbe.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, nil)
    stop = i64[1]
    pre.set_stop_cell(stop)
    pre.prepare
    expect(pre.try_eliminate(1)).to eq(true)
    before = pre.logical_snapshot
    pre.tighten
    expect(pre.try_eliminate(4)).to eq(false)
    expect(pre.cancelled).to eq(true)
    expect(pre.logical_snapshot).to eq(before)
    pre.set_stop_cell(nil)
    expect(pre.try_eliminate(4)).to eq(true)
    reuse_check_sat(pre, text)

  it "reuses native flat storage while retaining lazy reconstruction literals" ->
    text = "p cnf 6 4\n1 2 0\n-1 3 0\n4 5 0\n-4 6 0\n"
    # Flat intake is engine-independent; the native DIMACS parser is not.
    f = wassat_parse_cnf(text)
    lits = i64[8]
    offs = i64[4]
    lens = i64[4]
    values = [1, 2, -1, 3, 4, 5, -4, 6]
    i = 0
    while i < 8
      lits[i] = values[i]
      i += 1
    i = 0
    while i < 4
      offs[i] = 2 * i
      lens[i] = 2
      i += 1
    f["flat_lits"] = lits
    f["flat_offs"] = offs
    f["flat_lens"] = lens
    f["flat_ncl"] = 4
    f["flat_nlits"] = 8
    pre = StorageReuseProbe.new(f["nvars"], [], WASSAT_PROOF_NONE, f)
    pre.prepare_flat(f)
    expect(pre.try_eliminate(1)).to eq(true)
    pre.tighten
    expect(pre.try_eliminate(4)).to eq(true)
    expect(pre.artifact["stats"]["storage_compactions"]).to eq(1)
    reuse_check_sat(pre, text)

  it "keeps root reasons and independently verifiable certificates after a unit commit" ->
    text = "p cnf 2 4\n1 2 0\n-1 2 0\n1 -2 0\n-1 -2 0\n"
    f = wassat_parse_cnf(text)
    pre = StorageReuseProbe.new(f["nvars"], f["clauses"], WASSAT_PROOF_WRAT, nil)
    pre.prepare
    expect(pre.try_eliminate(1)).to eq(true)
    before = pre.logical_snapshot
    pre.compact_live_storage
    expect(pre.logical_snapshot).to eq(before)
    art = pre.artifact
    expect(art["status"]).to eq(-1)
    proof = "wrat 1\n" + art["wrat"].join("\n") + "\n"
    expect(wrat_verify(text, proof)["verified"]).to eq(true)



# Pack before adding a second pivot's unit resolvents, then verify the whole
# resulting proof independently. Renaming, signs and clause order vary.
describe "BVE storage reuse proof ordering" ->
  it "preserves proof references across compaction and a later refutation" ->
    seed = 0
    while seed < 12
      source = [[1, 2], [-1, 3], [4, 5], [-4, 5], [4, -5], [-4, -5]]
      clauses = []
      i = 0
      while i < source.size
        ci = (i + seed) % source.size
        row = []
        source[ci].each -> (l)
          v = (l.abs - 1 + seed) % 5 + 1
          sign = (v + seed) % 2 == 0 ? -1 : 1
          row.push((l < 0 ? 0 - sign : sign) * v)
        clauses.push(row)
        i += 1
      text = "p cnf 5 6\n"
      clauses.each -> (row)
        text += row.join(" ") + " 0\n"
      pre = StorageReuseProbe.new(5, clauses, WASSAT_PROOF_WRAT, nil)
      pre.prepare
      expect(pre.try_eliminate(seed % 5 + 1)).to eq(true)
      pre.tighten
      expect(pre.try_eliminate((3 + seed) % 5 + 1)).to eq(true)
      art = pre.artifact
      expect(art["stats"]["storage_compactions"]).to eq(1)
      expect(art["status"]).to eq(-1)
      proof = "wrat 1\n" + art["wrat"].join("\n") + "\n"
      expect(wrat_verify(text, proof)["verified"]).to eq(true)
      seed += 1

spec_summary
