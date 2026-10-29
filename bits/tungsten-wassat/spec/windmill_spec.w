use spec
use ../lib/windmill

-> windmill_flat_formula(text)
  f = wassat_parse_cnf(text)
  clauses = f["clauses"]
  total = 0
  clauses.each -> (clause)
    total += clause.size
  lits = i64[total + 1]
  offs = i64[clauses.size + 1]
  lens = i64[clauses.size + 1]
  offset = 0
  index = 0
  clauses.each -> (clause)
    offs[index] = offset
    lens[index] = clause.size
    clause.each -> (lit)
      lits[offset] = lit
      offset += 1
    index += 1
  f["flat_lits"] = lits
  f["flat_offs"] = offs
  f["flat_lens"] = lens
  f["flat_ncl"] = clauses.size
  f["flat_nlits"] = total
  f

# Clean-room structural fixture matching the windmill clause shapes:
#   - tri-state cell grid (consecutive exactly-one triples at stride 3*cols)
#   - carry-over clauses naming one distinct guard per (transition r, column c)
#   - fixed initial and final partition rows
#   - per-transition P pairs, T triples, and inactive flags
#   - optional V[0..rows-1, pair] monotone swap ladders with full 2x2 / ordering
#     clause families so wassat_windmill_recover_v and wassat_windmill_eval_native
#     are exercised end-to-end without any hardcoded variable numbers.
-> windmill_fixture(cols, rows, with_v = false, permute_guards = false, extra_lines = [])
  h = (cols - 1) / 2
  ntrans = rows - 1
  nmoves = ntrans - 1
  stride = 3 * cols
  npairs = (cols * (cols - 1)) / 2
  lines = []
  next_var = 1
  guard = i64[ntrans * cols]
  ng = ntrans * cols
  i = 0
  while i < ng
    idx = permute_guards ? ((i * 5 + 3) % ng) : i
    guard[idx] = next_var
    next_var += 1
    i += 1
  pvar = i64[ntrans]
  r = 0
  while r < ntrans
    pvar[r] = next_var
    next_var += 2
    r += 1
  tvar = i64[ntrans]
  r = 0
  while r < ntrans
    tvar[r] = next_var
    next_var += 3
    r += 1
  sbase = next_var
  next_var += rows * stride
  vvar = i64[rows * npairs]
  if with_v
    i = 0
    while i < rows * npairs
      vvar[i] = next_var
      next_var += 1
      i += 1
  # Flags live far from P pairs so (flag, p, p+1) is never a consecutive triple.
  flag = i64[ntrans]
  r = 0
  while r < ntrans
    flag[r] = next_var
    next_var += 1
    r += 1
  # State cells: exactly one of three.
  r = 0
  while r < rows
    c = 0
    while c < cols
      a = sbase + r * stride + 3 * c
      lines.push("[a] [a + 1] [a + 2] 0")
      lines.push("-[a] -[a + 1] 0")
      lines.push("-[a] -[a + 2] 0")
      lines.push("-[a + 1] -[a + 2] 0")
      c += 1
    r += 1
  # Carry-over for left/right states.
  r = 0
  while r < ntrans
    c = 0
    while c < cols
      g = guard[r * cols + c]
      k = 0
      while k < 2
        s = sbase + r * stride + 3 * c + k
        lines.push("[g] -[s] [s + stride] 0")
        lines.push("[g] [s] -[s + stride] 0")
        k += 1
      c += 1
    r += 1
  # Initial and final partition rows.
  c = 0
  while c < cols
    k0 = c < h ? 0 : (c == h ? 2 : 1)
    lines.push("[sbase + 3 * c + k0] 0")
    if c != h
      kf = c < h ? 1 : 0
      lines.push("[sbase + (rows - 1) * stride + 3 * c + kf] 0")
    c += 1
  # P pairs, flags, T triples, and row-attachment clauses.
  r = 0
  while r < ntrans
    p = pvar[r]
    f = flag[r]
    t = tvar[r]
    lines.push("-[p] -[p + 1] 0")
    lines.push("[f] [p] [p + 1] 0")
    lines.push("-[f] -[p] 0")
    lines.push("-[f] -[p + 1] 0")
    lines.push(r < nmoves ? "-[f] 0" : "[f] 0")
    lines.push("[f] [t] [t + 1] [t + 2] 0")
    lines.push("-[t] -[t + 1] 0")
    lines.push("-[t] -[t + 2] 0")
    lines.push("-[t + 1] -[t + 2] 0")
    k = 0
    while k < 3
      lines.push("-[t + k] [p] [p + 1] 0")
      k += 1
    s = sbase + r * stride + 3 * h + 2
    lines.push("-[p] -[s] [s + stride - 2] 0")
    lines.push("-[p + 1] -[s] [s + stride - 1] 0")
    if r >= nmoves
      c = 0
      while c < cols
        lines.push("-[guard[r * cols + c]] 0")
        c += 1
    r += 1
  if with_v
    c1 = 0
    while c1 < cols
      c2 = c1 + 1
      while c2 < cols
        pi = wassat_windmill_pair_index(cols, c1, c2)
        r = 0
        while r < ntrans
          g1 = guard[r * cols + c1]
          g2 = guard[r * cols + c2]
          vr = vvar[r * npairs + pi]
          vr1 = vvar[(r + 1) * npairs + pi]
          lines.push("-[g1] -[g2] [vr] 0")
          lines.push("-[g1] -[g2] -[vr1] 0")
          lines.push("[vr] -[vr1] 0")
          r += 1
        c2 += 1
      c1 += 1
  i = 0
  while i < extra_lines.size
    lines.push(extra_lines[i])
    i += 1
  "p cnf [next_var - 1] [lines.size]\n" + lines.join("\n") + "\n"

describe "Wassat allowable-sequence windmill lane" ->
  it "recovers the layout of a windmill-shaped formula even under permuted guard IDs" ->
    formula = windmill_flat_formula(windmill_fixture(7, 4, false, true))
    lay = wassat_windmill_recognize(formula)
    expect(lay == nil).to eq(false)
    expect(lay["cols"]).to eq(7)
    expect(lay["h"]).to eq(3)
    expect(lay["rows"]).to eq(4)
    expect(lay["stride"]).to eq(21)
    expect(lay["nmoves"]).to eq(2)
    expect(lay["mirror_sym"]).to eq(true)
    active = lay["active"] ## i8[]
    expect(active[0]).to eq(1)
    expect(active[1]).to eq(1)
    expect(active[2]).to eq(0)
    guard = lay["guard"] ## i64[]
    # idx = (i * 5 + 3) % 21: i=0 -> guard[3] == 1
    expect(guard[3]).to eq(1)
    pvar = lay["pvar"] ## i64[]
    tvar = lay["tvar"] ## i64[]
    expect(pvar[0]).to eq(22)
    expect(pvar[1]).to eq(24)
    expect(tvar[0]).to eq(28)
    expect(tvar[2]).to eq(34)

  it "emits involution clauses for active moves only and detects asymmetric units" ->
    formula = windmill_flat_formula(windmill_fixture(7, 4))
    lay = wassat_windmill_recognize(formula)
    extra = wassat_windmill_mirror_clauses(lay)
    # 7 guard pairs x 2 + P 2 x 2 + T 3 x 2 + halfway median unit
    expect(extra.size).to eq(14 + 4 + 6 + 1)
    expect(extra[0]).to eq([-1, 14])
    expect(extra[1]).to eq([1, -14])
    last = extra[extra.size - 1]
    expect(last.size).to eq(1)

    asym = windmill_flat_formula(windmill_fixture(7, 4, false, false, ["-1 0"]))
    alay = wassat_windmill_recognize(asym)
    expect(alay == nil).to eq(false)
    expect(alay["mirror_sym"]).to eq(false)

  it "misses non-windmill formulas" ->
    formula = windmill_flat_formula("p cnf 3 2\n1 2 0\n-1 3 0\n")
    expect(wassat_windmill_recognize(formula) == nil).to eq(true)

  it "recovers V swap ladders and detects 2x2 rectangles and surviving cut positions natively" ->
    formula = windmill_flat_formula(windmill_fixture(7, 5, true))
    lay = wassat_windmill_recognize(formula)
    expect(lay == nil).to eq(false)
    vinfo = wassat_windmill_recover_v(formula, lay)
    expect(vinfo == nil).to eq(false)
    npairs = vinfo["npairs"]
    expect(npairs).to eq(21)

    nv = formula["nvars"]
    mval = i8[nv + 2]
    v = 1
    while v <= nv
      mval[v] = -1
      v += 1
    guard = lay["guard"] ## i64[]
    # Force a 2x2 rectangle on active rows 0 and 2, columns 1 and 4:
    mval[guard[0 * 7 + 1]] = 1
    mval[guard[0 * 7 + 4]] = 1
    mval[guard[2 * 7 + 1]] = 1
    mval[guard[2 * 7 + 4]] = 1

    nmoves = lay["nmoves"]
    rect_seen = i8[nmoves * nmoves * npairs]
    rect_out = i64[64]
    bad_pairs = i64[npairs]
    order_bad = i64[npairs]
    pair_kstar = i64[npairs]
    row_hits = i64[nmoves]
    eval_st = i64[4]
    wassat_windmill_eval_native(
      mval, guard, vinfo["g_row"], vinfo["root_mask"], vinfo["pair_pc_off"],
      vinfo["pc_kill"], vinfo["pc_lits_off"], vinfo["pc_lits_len"], vinfo["pc_lits"],
      rect_seen, rect_out, 16,
      bad_pairs, order_bad, pair_kstar, row_hits,
      7, nmoves, npairs, eval_st
    )
    expect(eval_st[0]).to eq(1)
    expect(eval_st[1]).to eq(1)
    expect(eval_st[2]).to eq(0)
    expect(bad_pairs[0]).to eq(wassat_windmill_pair_index(7, 1, 4))
    expect(rect_out[0]).to eq(0 - guard[0 * 7 + 1])
    expect(rect_out[1]).to eq(0 - guard[0 * 7 + 4])
    expect(rect_out[2]).to eq(0 - guard[2 * 7 + 1])
    expect(rect_out[3]).to eq(0 - guard[2 * 7 + 4])

  it "solves asymmetric V-ladder windmills via CEGAR/portfolio and verifies the full model" ->
    # Forbid mirror symmetry on guard(0,0) vs guard(2,6) so Stage 1 mirror probe
    # refutes immediately and Stage 2 CEGAR + --sat portfolio must find SAT!
    # Also include a wide (>16-literal) non-V guard clause to cover wide-clause Pass 2.
    wide_guard = "1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 0"
    asym_cnf = windmill_fixture(7, 5, true, false, ["1 0", "-21 0", wide_guard])
    formula = windmill_flat_formula(asym_cnf)
    res = wassat_windmill_solve(formula, { "status": 0 }, 200000)
    expect(res["recognized"]).to eq(true)
    expect(res["status"]).to eq(1)
    expect(wassat_model_satisfies?(formula, res["model"])).to eq(true)

  it "projects short V-free pair-cut conflict clauses and isolates the (P, T) master subformula" ->
    # Add two state-order V-clauses on pair (1, 4):
    #   (-G[0,1], -V[1,p]) kills cuts 1..5 when G[0,1] = 1
    #   (-G[2,4], +V[1,p]) kills cuts 0..1 when G[2,4] = 1
    # Together under G[0,1] = 1, G[2,4] = 1 (without a 2x2 rectangle!), no cut
    # position survives and wassat_windmill_project_pair_cuts must emit [-G[0,1], -G[2,4]].
    base = windmill_flat_formula(windmill_fixture(7, 5, true))
    blay = wassat_windmill_recognize(base)
    bv = wassat_windmill_recover_v(base, blay)
    p14 = wassat_windmill_pair_index(7, 1, 4)
    npairs = bv["npairs"]
    v1 = bv["vvar"][1 * npairs + p14]
    g01 = blay["guard"][0 * 7 + 1]
    g24 = blay["guard"][2 * 7 + 4]
    formula = windmill_flat_formula(
      windmill_fixture(7, 5, true, false, ["-[g01] -[v1] 0", "-[g24] [v1] 0"])
    )
    lay = wassat_windmill_recognize(formula)
    vinfo = wassat_windmill_recover_v(formula, lay)
    expect(vinfo == nil).to eq(false)
    master = wassat_windmill_build_pt_master(formula, lay, vinfo)
    expect(master == nil).to eq(false)
    mres = master.solve_budget(0)
    expect(mres["status"]).to eq(1)

    nv = formula["nvars"]
    mval = i8[nv + 2]
    v = 1
    while v <= nv
      mval[v] = -1
      v += 1
    mval[g01] = 1
    mval[g24] = 1
    nmoves = lay["nmoves"]
    rect_seen = i8[nmoves * nmoves * npairs]
    rect_out = i64[64]
    bad_pairs = i64[npairs]
    order_bad = i64[npairs]
    pair_kstar = i64[npairs]
    row_hits = i64[nmoves]
    eval_st = i64[4]
    wassat_windmill_eval_native(
      mval, lay["guard"], vinfo["g_row"], vinfo["root_mask"], vinfo["pair_pc_off"],
      vinfo["pc_kill"], vinfo["pc_lits_off"], vinfo["pc_lits_len"], vinfo["pc_lits"],
      rect_seen, rect_out, 16,
      bad_pairs, order_bad, pair_kstar, row_hits,
      7, nmoves, npairs, eval_st
    )
    expect(eval_st[0]).to eq(0)
    expect(eval_st[1]).to eq(1)
    expect(eval_st[2]).to eq(1)
    proj_seen = i64[128]
    pcuts = wassat_windmill_project_pair_cuts(
      mval, order_bad, eval_st[2], vinfo["root_mask"], vinfo["pair_pc_off"],
      vinfo["pc_kill"], vinfo["pc_lits_off"], vinfo["pc_lits_len"],
      vinfo["pc_lits"], proj_seen, 16
    )
    expect(pcuts.size).to eq(1)
    lo_lit = (0 - g01) < (0 - g24) ? (0 - g01) : (0 - g24)
    hi_lit = (0 - g01) < (0 - g24) ? (0 - g24) : (0 - g01)
    expect(pcuts[0]).to eq([lo_lit, hi_lit])

    # Verify two-tier primary decision ordering, best-phase export, and
    # zero-allocation retired-arena recovery on a fixed-cap solver.
    raw_art = wassat_raw_artifact(formula, nv)
    orders = wassat_windmill_var_orders(nv, lay, vinfo)
    s = Wassat.from_flat(nv, raw_art, 0)
    s.enable_fixed_caps
    s.set_primary_decision_vars(orders["ptgs_vars"])
    s.install_pruning_clause(pcuts[0], false, true)
    expect(s.recover_retired_arena).to eq(1)
    bp = i8[nv + 2]
    s.export_best_phase(bp)
    expect(bp[1] == 1 || bp[1] == -1).to eq(true)
    sres = s.solve_budget(50000)
    expect(sres["status"]).to eq(1)
    expect(wassat_model_satisfies?(formula, sres["model"])).to eq(true)

  it "fails open with status 0 on unsatisfiable windmill formulas" ->
    unsat_cnf = windmill_fixture(7, 4, true, false, ["1 0", "-1 0"])
    formula = windmill_flat_formula(unsat_cnf)
    res = wassat_windmill_solve(formula, { "status": 0 }, 50000)
    expect(res["recognized"]).to eq(true)
    expect(res["status"]).to eq(0)

spec_summary
