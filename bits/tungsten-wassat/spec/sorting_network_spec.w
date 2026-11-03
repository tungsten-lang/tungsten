use spec
use ../lib/wassat

-> sorting_flat_fixture(f)
  cs = f["clauses"]; total = 0
  cs.each -> (c) total += c.size
  lits = i64[total]; offs = i64[cs.size]; lens = i64[cs.size]
  i = 0; at = 0
  cs.each -> (c)
    offs[i] = at; lens[i] = c.size
    c.each -> (v)
      lits[at] = v; at += 1
    i += 1
  { "nvars": f["nvars"], "clauses": cs, "boxed": true,
    "flat_ncl": cs.size, "flat_nlits": total,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

-> sorting_fixture(pattern)
  n = 8; depth = 3; ids = i32[depth*n*n]; next_var = 1; cs = []
  l = 0
  while l < depth
    a = 0
    while a < n
      b = a+1
      while b < n
        if l < depth-1 || b == a+1
          ids[(l*n+a)*n+b] = next_var; ids[(l*n+b)*n+a] = next_var
          next_var += 1
        b += 1
      a += 1
    l += 1
  flag_base = next_var; next_var += n*depth
  l = 0
  while l < depth
    a = 0
    while a < n
      row = []
      b = 0
      while b < n
        id = ids[(l*n+a)*n+b]
        row.push(id) if id > 0
        b += 1
      i = 0
      while i < row.size
        j = i+1
        while j < row.size
          cs.push([-row[i],-row[j]]); j += 1
        i += 1
      a += 1
    l += 1
  l = 0
  while l < depth
    a = 0
    while a < n
      flag = flag_base+l*n+a; row = [-flag]; b = 0
      while b < n
        id = ids[(l*n+a)*n+b]
        if id > 0
          row.push(id); cs.push([-id,flag])
        b += 1
      cs.push(row); a += 1
    l += 1
  # Enough exact idle-wire clauses to test extraction, connected into one
  # signal component. This fixture tests decoding, not sorting semantics.
  first_signal = next_var
  a = 0
  while a < n
    cs.push([flag_base+a,(pattern & (1<<a)) != 0 ? next_var : -next_var])
    cs.push([-first_signal,next_var]) if a > 0
    next_var += 1; a += 1
  f = { "nvars": next_var-1, "clauses": cs }
  { "formula": sorting_flat_fixture(f), "ids": ids }

-> sorting_test_arrays(n, depth)
  allowed = i32[depth*n*n]; l = 0; id = 1
  while l < depth
    a = 0
    while a < n
      b = a+1
      while b < n
        allowed[(l*n+a)*n+b] = id; allowed[(l*n+b)*n+a] = id; id += 1; b += 1
      a += 1
    l += 1
  allowed

-> sorting_scalar(pattern, mate, n, depth)
  l = 0
  while l < depth
    a = 0
    while a < n
      b = mate[l*n+a]
      if b > a && (pattern & (1<<a)) != 0 && (pattern & (1<<b)) == 0
        pattern ^= (1<<a) | (1<<b)
      a += 1
    l += 1
  pattern

describe "Input-derived comparator search" ->
  it "bounds the total arena reservation by RAM and the process envelope" ->
    expect(wassat_sorting_memory_allowed(6442450944,25769803776)).to eq(1)
    expect(wassat_sorting_memory_allowed(6442450945,25769803776)).to eq(0)
    expect(wassat_sorting_memory_allowed(3000000000,6000000000)).to eq(0)
    expect(wassat_sorting_memory_allowed(1,0)).to eq(0)
  it "extracts matching layers and component input bits" ->
    fix = sorting_fixture(170); m = i64[32]; stop = i64[4]
    d = wassat_sorting_decode(fix["formula"],m,stop,clock_ms()+5000)
    expect(d != nil).to eq(true)
    expect(m[0]).to eq(8); expect(m[1]).to eq(3); expect(m[2]).to eq(63)
    expect(m[4]).to eq(1); expect(d["vectors"][0]).to eq(170)
    expected = fix["ids"]; actual = d["allowed"]; i = 0; same = true
    while i < expected.size
      same = false if expected[i] != actual[i]; i += 1
    expect(same).to eq(true)
  it "keeps later selector aliases outside the participation flag block" ->
    fix = sorting_fixture(170); f = fix["formula"]; cs = f["clauses"]
    alias = f["nvars"]+1; cs.push([-alias,1]); cs.push([alias,-1])
    changed = sorting_flat_fixture({ "nvars": alias, "clauses": cs })
    m = i64[32]; d = wassat_sorting_decode(changed,m,i64[4],clock_ms()+5000)
    expect(d != nil).to eq(true)
    expect(m[3]).to eq(87); expect(m[4]).to eq(1)
    expect(d["vectors"][0]).to eq(170)
  it "rejects a missing matching exclusion" ->
    fix = sorting_fixture(170); f = fix["formula"]
    f["flat_lits"][0] = 1
    expect(wassat_sorting_decode(f,i64[32],i64[4],clock_ms()+5000)).to eq(nil)
  it "rejects contradictory idle values" ->
    fix = sorting_fixture(170); f = fix["formula"]
    cs = f["clauses"]; cs.push([64,88])
    changed = sorting_flat_fixture({ "nvars": f["nvars"], "clauses": cs })
    expect(wassat_sorting_decode(changed,i64[32],i64[4],clock_ms()+5000)).to eq(nil)
  it "finds a small network checked by scalar simulation of every input" ->
    m = i64[32]; m[0] = 4; m[1] = 3; m[4] = 80
    vectors = i32[80]; i = 0
    while i < 80
      vectors[i] = i%16; i += 1
    mate = i8[12]
    r = wassat_sorting_search(sorting_test_arrays(4,3),vectors,mate,m,i64[4],clock_ms()+10000,100000)
    expect(r).to eq(1)
    i = 0; ok = true
    while i < 16
      target = ((1<<popcount(i))-1) << (4-popcount(i))
      ok = false if sorting_scalar(i,mate,4,3) != target
      i += 1
    expect(ok).to eq(true)
  it "honors cancellation before search" ->
    m = i64[32]; m[0] = 4; m[1] = 3; m[4] = 1; stop = i64[4]
    z = wassat_stop_cancel(stop)
    expect(wassat_sorting_search(sorting_test_arrays(4,3),i32[1],i8[12],m,stop,clock_ms()+10000,1000)).to eq(0)
    expect(m[10]).to eq(1); expect(m[6]).to eq(0)
  it "honors expired deadlines" ->
    m = i64[32]; m[0] = 4; m[1] = 3; m[4] = 1
    expect(wassat_sorting_search(sorting_test_arrays(4,3),i32[1],i8[12],m,i64[4],0,1000)).to eq(0)
    expect(m[10]).to eq(2)
  it "completes a residual and validates all original clauses" ->
    f = sorting_flat_fixture({ "nvars": 4, "clauses": [[1,2],[-1,2],[1,-2]] })
    m = i64[32]; m[0] = 2; m[1] = 1; res = i64[12]; mate = i8[2]
    mate[0] = -1; mate[1] = -1
    expect(wassat_sorting_complete(f,i32[4],mate,m,i64[4],clock_ms()+5000,res,0)).to eq(1)
    expect(m[13]).to eq(3); expect(m[18]).to eq(1)
    expect(res[1]).to eq(1); expect(res[2]).to eq(1)
  it "leaves contradictory completions unpublished" ->
    f = sorting_flat_fixture({ "nvars": 4, "clauses": [[1],[-1]] })
    m = i64[32]; m[0] = 4; m[1] = 1; res = i64[12]
    expect(wassat_sorting_complete(f,i32[16],i8[4],m,i64[4],clock_ms()+5000,res,0)).to eq(0)
    expect(res[0]).to eq(0)

spec_summary
