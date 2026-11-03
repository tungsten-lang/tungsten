use spec
use ../lib/wassat

-> sd_flat(nv,rows)
  total = 0
  rows.each -> (row) total += row.size
  lits = i64[total]; offs = i64[rows.size]; lens = i64[rows.size]; at = 0; i = 0
  rows.each -> (row)
    offs[i] = at; lens[i] = row.size
    row.each -> (v)
      lits[at] = v; at += 1
    i += 1
  { "nvars": nv, "clauses": rows, "flat_ncl": rows.size, "flat_nlits": total,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

-> sd_replay(rows,res)
  rows.each -> (row)
    ok = false
    row.each -> (lit)
      v = lit < 0 ? -lit : lit
      ok = true if (res[v] == 1) == (lit > 0)
    return false unless ok
  true

-> sd_check_run(nv,rows,steps=1000)
  f = sd_flat(nv,rows); m = i64[32]; res = i64[nv+8]
  hit = wassat_sparse_domain_run(f,m,i64[4],res,0,0,1,steps)
  { "hit": hit, "meta": m, "res": res }

-> sd_clique(n,k)
  rows = []; a = 0
  while a < n
    row = []; c = 0
    while c < k
      row.push(a*k+c+1); c += 1
    rows.push(row); a += 1
  a = 0
  while a < n
    b = a+1
    while b < n
      c = 0
      while c < k
        rows.push([-a*k-c-1,-b*k-c-1]); c += 1
      b += 1
    a += 1
  rows

-> sd_oracle(rows,n,k)
  state = 0; limit = 1
  n.times -> limit *= k
  while state < limit
    code = state; res = i64[n*k+1]; b = 0
    while b < n
      res[b*k+(code%k)+1] = 1; code /= k; b += 1
    return true if sd_replay(rows,res)
    state += 1
  false

describe "Sparse finite-domain search" ->
  it "builds sparse exclusions and checks the complete original model" ->
    rows = [[1,2,3],[4,5,6],[-1,-4],[-2,-5],[-3,-6]]
    r = sd_check_run(6,rows)
    expect(r["hit"]).to eq(1); expect(r["meta"][16]).to eq(1)
    expect(r["meta"][14]).to eq(rows.size); expect(r["meta"][25]).to eq(3)
    expect(sd_replay(rows,r["res"])).to eq(true)
  it "accepts permuted duplicate rows and repeated exclusions" ->
    rows = [[1,2,3],[4,5,6],[3,1,2],[-1,-4],[-4,-1],[-2,-5]]
    r = sd_check_run(6,rows)
    expect(r["hit"]).to eq(1); expect(sd_replay(rows,r["res"])).to eq(true)
    expect(r["meta"][25]).to eq(3)
  it "propagates singleton domains through a chain of exclusions" ->
    rows = [[1],[2,3],[4,5],[-1,-2],[-3,-4]]
    r = sd_check_run(5,rows)
    expect(r["hit"]).to eq(1); expect(r["meta"][24]).to eq(2)
    expect(r["res"][1]).to eq(1); expect(r["res"][3]).to eq(1); expect(r["res"][5]).to eq(1)
  it "honors positive units and repeated-literal negative units" ->
    rows = [[1,2,3],[4,5,6],[2],[-4,-4],[-6],[-1,-5]]
    r = sd_check_run(6,rows)
    expect(r["hit"]).to eq(1); expect(r["res"][2]).to eq(1); expect(r["res"][5]).to eq(1)
    expect(sd_replay(rows,r["res"])).to eq(true)
  it "declines contradictory units without publishing a verdict" ->
    r = sd_check_run(4,[[1,2],[3,4],[1],[2]])
    expect(r["hit"]).to eq(0); expect(r["res"][0]).to eq(0); expect(r["meta"][16]).to eq(0)
  it "declines overlapping domains and unsupported residual clauses" ->
    expect(sd_check_run(4,[[1,2],[2,3,4]])["hit"]).to eq(0)
    expect(sd_check_run(4,[[1,2],[3,4],[-1,3]])["hit"]).to eq(0)
    expect(sd_check_run(4,[[1,2],[3,4],[-1,-2,-3]])["hit"]).to eq(0)
  it "declines duplicate row variables and uncovered variables" ->
    expect(sd_check_run(4,[[1,2,1],[3,4]])["hit"]).to eq(0)
    expect(sd_check_run(5,[[1,2],[3,4]])["hit"]).to eq(0)
  it "declines invalid flat offsets before reading literals" ->
    f = sd_flat(4,[[1,2],[3,4]]); f["flat_offs"][1] = 99
    expect(wassat_sparse_domain_prepare(f,i64[32],i64[4],0)).to eq(nil)
  it "treats exhausted search as unknown, even for a finite UNSAT graph" ->
    rows = sd_clique(4,3); expect(sd_oracle(rows,4,3)).to eq(false)
    r = sd_check_run(12,rows,100)
    expect(r["hit"]).to eq(0); expect(r["meta"][2]).to eq(3)
    expect(r["meta"][16]).to eq(0); expect(r["res"][0]).to eq(0)
  it "agrees with small exhaustive coloring oracles" ->
    n = 2
    while n <= 5
      k = 2
      while k <= 4
        rows = sd_clique(n,k); expected = sd_oracle(rows,n,k)
        r = sd_check_run(n*k,rows,1000)
        expect(r["hit"] == 1).to eq(expected)
        expect(sd_replay(rows,r["res"])).to eq(true) if r["hit"] == 1
        k += 1
      n += 1
  it "maintains exact weighted costs and the active list after many moves" ->
    f = sd_flat(12,sd_clique(4,3)); m = i64[32]; stop = i64[4]
    d = wassat_sparse_domain_prepare(f,m,stop,0)
    owner = d["owner"]; values = d["values"]; first = d["first"]; allowed = d["allowed"]
    heads = d["heads"]; edges = d["edges"]; ids = d["ids"]
    sol = i32[4]; counts = i32[13]; costs = i64[13]; weights = i32[d["ne"]]
    bad = i32[4]; pos = i32[4]; st = i64[4]; m[13] = d["ne"]
    hit = wassat_sparse_domain_trial(owner,values,first,allowed,heads,edges,ids,sol,counts,costs,weights,bad,pos,st,m,stop,12,4,1,256,0)
    expect(hit).to eq(0); expect(m[8] > 0).to eq(true); expect(m[9] > 0).to eq(true)
    v = 1; violations = 0; active = 0
    while v <= 12
      count = 0; cost = 0; p = heads[v]
      while p < heads[v+1]
        u = edges[p]
        if sol[owner[u]-1] == u
          count += 1; cost += weights[ids[p]]
        p += 1
      expect(counts[v]).to eq(count); expect(costs[v]).to eq(cost)
      b = owner[v]-1
      if sol[b] == v
        violations += count
        expect(pos[b] > 0).to eq(count > 0)
        if count > 0
          active += 1; expect(bad[pos[b]-1]).to eq(b)
      v += 1
    expect(st[0]).to eq(active); expect(2*st[1]).to eq(violations)
  it "checks a candidate against exclusions outside its search state" ->
    f = sd_flat(4,[[1,2],[3,4],[-1,-3]]); owner = i32[5]; owner[1] = 1; owner[2] = 1; owner[3] = 2; owner[4] = 2
    sol = i32[2]; sol[0] = 1; sol[1] = 3; m = i64[32]
    expect(wassat_sparse_domain_verify(f["flat_lits"],f["flat_offs"],f["flat_lens"],3,owner,sol,m,i64[4],0)).to eq(0)
    expect(m[16]).to eq(0)
  it "honors cancellation and deadline before preparation" ->
    f = sd_flat(4,[[1,2],[3,4]]); stop = i64[4]; z = wassat_stop_cancel(stop); m = i64[32]
    expect(wassat_sparse_domain_prepare(f,m,stop,0)).to eq(nil); expect(m[2]).to eq(1)
    m = i64[32]
    expect(wassat_sparse_domain_prepare(f,m,i64[4],1)).to eq(nil); expect(m[2]).to eq(2)
  it "bounds its memory reservation by both RAM and the process envelope" ->
    expect(wassat_sparse_domain_memory_allowed(6442450944,25769803776)).to eq(1)
    expect(wassat_sparse_domain_memory_allowed(6442450945,25769803776)).to eq(0)
    expect(wassat_sparse_domain_memory_allowed(3000000000,6000000000)).to eq(0)
    expect(wassat_sparse_domain_memory_allowed(1,0)).to eq(0)

spec_summary
