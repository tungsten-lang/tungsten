use spec
use wassat

# Two-color arithmetic hypergraphs rendered directly as monochromatic
# nogoods: an all-positive clause forbids all-false, an all-negative one
# forbids all-true over the scope.

-> arith_render(nv, scopes)
  lines = []
  scopes.each -> (scope)
    lines.push(scope.join(" ") + " 0")
    neg = []
    scope.each -> (v)
      neg.push(0 - v)
    lines.push(neg.join(" ") + " 0")
  "p cnf [nv] [lines.size]\n" + lines.join("\n") + "\n"

-> arith_ap_scopes(n, k)
  scopes = []
  start = 1
  while start <= n
    d = 1
    while start + (k - 1) * d <= n
      scope = []
      i = 0
      while i < k
        scope.push(start + i * d)
        i += 1
      scopes.push(scope)
      d += 1
    start += 1
  scopes

-> arith_schur_scopes(n)
  scopes = []
  x = 1
  while x <= n
    y = x
    while y <= n
      if x + y <= n
        scope = []
        [x, y, x + y].each -> (v)
          scope.push(v) unless scope.include?(v)
        scopes.push(scope)
      y += 1
    x += 1
  scopes

-> arith_ramsey_scopes(nverts)
  edge_id = i64[nverts * nverts]
  idx = 1
  i = 0
  while i < nverts
    j = i + 1
    while j < nverts
      edge_id[i * nverts + j] = idx
      idx += 1
      j += 1
    i += 1
  scopes = []
  i = 0
  while i < nverts
    j = i + 1
    while j < nverts
      k = j + 1
      while k < nverts
        scopes.push([
          edge_id[i * nverts + j],
          edge_id[i * nverts + k],
          edge_id[j * nverts + k]
        ])
        k += 1
      j += 1
    i += 1
  scopes

-> arith_paired_ap_cnf(n, k)
  lines = []
  i = 0
  while i < n
    lo = 2 * i + 1
    lines.push("[lo] [lo + 1] 0")
    lines.push("[0 - lo] [0 - (lo + 1)] 0")
    i += 1
  arith_ap_scopes(n, k).each -> (scope)
    [1, 2].each -> (offset)
      lits = []
      scope.each -> (v)
        lits.push(0 - (2 * (v - 1) + offset))
      lines.push(lits.join(" ") + " 0")
  "p cnf [2 * n] [lines.size]\n" + lines.join("\n") + "\n"

describe "Wassat arithmetic two-coloring" ->
  it "colors [1..8] without a monochromatic 3-AP and refutes [1..9]" ->
    res = wassat_arith_coloring_solve(
      wassat_parse_cnf_native(arith_render(8, arith_ap_scopes(8, 3)))
    )
    expect(res["family"]).to eq("van-der-waerden")
    expect(res["status"]).to eq(1)
    res9 = wassat_arith_coloring_solve(
      wassat_parse_cnf_native(arith_render(9, arith_ap_scopes(9, 3)))
    )
    expect(res9["status"]).to eq(-1)

  it "decides the paired encoding of the same Van der Waerden shape" ->
    res = wassat_arith_coloring_solve(
      wassat_parse_cnf_native(arith_paired_ap_cnf(8, 3))
    )
    expect(res["status"]).to eq(1)
    res9 = wassat_arith_coloring_solve(
      wassat_parse_cnf_native(arith_paired_ap_cnf(9, 3))
    )
    expect(res9["status"]).to eq(-1)

  it "decides Schur at its threshold (4 colorable, 5 not)" ->
    res = wassat_arith_coloring_solve(
      wassat_parse_cnf_native(arith_render(4, arith_schur_scopes(4)))
    )
    expect(res["family"]).to eq("schur")
    expect(res["status"]).to eq(1)
    res5 = wassat_arith_coloring_solve(
      wassat_parse_cnf_native(arith_render(5, arith_schur_scopes(5)))
    )
    expect(res5["status"]).to eq(-1)

  it "decides Ramsey R(3,3) (K5 colorable, K6 not)" ->
    res = wassat_arith_coloring_solve(
      wassat_parse_cnf_native(arith_render(10, arith_ramsey_scopes(5)))
    )
    expect(res["family"]).to eq("ramsey")
    expect(res["status"]).to eq(1)
    res6 = wassat_arith_coloring_solve(
      wassat_parse_cnf_native(arith_render(15, arith_ramsey_scopes(6)))
    )
    expect(res6["status"]).to eq(-1)

  it "falls through when one scope is not an arithmetic progression" ->
    scopes = arith_ap_scopes(9, 3)
    scopes.push([1, 2, 4])
    res = wassat_arith_coloring_solve(
      wassat_parse_cnf_native(arith_render(9, scopes))
    )
    expect(res["recognized"]).to eq(false)

describe "Wassat arithmetic color symmetry" ->
  it "requires matching scopes even when color and width counts match" ->
    scopes = arith_ap_scopes(9, 3)
    lines = []
    i = 0
    scopes.each -> (scope)
      # Replace (1,2,3) with a duplicate of (1,3,5), leaving its negative
      # partner intact. Counts stay balanced, but complementation is no
      # longer a symmetry. The unique model assigns the first branch
      # element, 5, true, so blindly fixing it false would be unsound.
      positive = i == 0 ? [1, 3, 5] : scope
      lines.push(positive.join(" ") + " 0")
      neg = []
      scope.each -> (v)
        neg.push(0 - v)
      lines.push(neg.join(" ") + " 0")
      i += 1
    text = "p cnf 9 [lines.size]\n" + lines.join("\n") + "\n"
    formula = wassat_parse_cnf_native(text)
    result = wassat_arith_coloring_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(result["model"].include?(5)).to eq(true)
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

spec_summary
