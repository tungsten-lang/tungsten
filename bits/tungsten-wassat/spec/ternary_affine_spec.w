use spec
use wassat

-> ternary_affine_cnf(ngroups, equations)
  lines = []
  g = 0
  while g < ngroups
    a = g * 3 + 1
    b = a + 1
    c = a + 2
    lines.push("[a] [b] [c] 0")
    lines.push("-[a] -[b] 0")
    lines.push("-[a] -[c] 0")
    lines.push("-[b] -[c] 0")
    g += 1

  equations.each -> (eq)
    groups = eq[0]
    coeff = eq[1]
    rhs = eq[2]
    pattern = 0
    while pattern < 81
      q = pattern
      v3 = q % 3
      q /= 3
      v2 = q % 3
      q /= 3
      v1 = q % 3
      q /= 3
      v0 = q % 3
      values = [v0, v1, v2, v3]
      dot = 0
      i = 0
      while i < 4
        dot += coeff[i] * values[i]
        i += 1
      if dot % 3 != rhs
        clause = []
        i = 0
        while i < 4
          clause.push(0 - (groups[i] * 3 + values[i] + 1))
          i += 1
        lines.push(clause.join(" ") + " 0")
      pattern += 1
  "p cnf [ngroups * 3] [lines.size]\n" + lines.join("\n") + "\n"

-> ternary_affine_reverse_cnf(text)
  input = text.split("\n")
  clauses = []
  i = 1
  while i < input.size
    line = input[i].strip
    unless line.empty?
      toks = line.split(" ")
      rev = []
      j = toks.size - 2
      while j >= 0
        rev.push(toks[j])
        j -= 1
      rev.push("0")
      clauses.push(rev.join(" "))
    i += 1
  out = []
  i = clauses.size - 1
  while i >= 0
    out.push(clauses[i])
    i -= 1
  input[0] + "\n" + out.join("\n") + "\n"

-> ternary_affine_interleave_cnf(text, ngroups, nequations)
  input = text.split("\n")
  clauses = []
  shell = 4 * ngroups
  i = 0
  while i < shell
    clauses.push(input[i + 1])
    i += 1
  pattern = 0
  while pattern < 54
    equation = 0
    while equation < nequations
      line = input[1 + shell + equation * 54 + pattern]
      toks = line.split(" ")
      rev = []
      j = toks.size - 2
      while j >= 0
        rev.push(toks[j])
        j -= 1
      rev.push("0")
      clauses.push(rev.join(" "))
      equation += 1
    pattern += 1
  input[0] + "\n" + clauses.join("\n") + "\n"

-> ternary_affine_brute_status(ngroups, equations)
  limit = 1
  i = 0
  while i < ngroups
    limit *= 3
    i += 1
  choice = i64[ngroups]
  state = 0
  while state < limit
    q = state
    i = 0
    while i < ngroups
      choice[i] = q % 3
      q /= 3
      i += 1
    ok = true
    equations.each -> (eq)
      dot = 0
      j = 0
      while j < 4
        dot += eq[1][j] * choice[eq[0][j]]
        j += 1
      ok = false unless dot % 3 == eq[2]
    return 1 if ok
    state += 1
  -1

describe "Wassat exact ternary-affine shortcut" ->
  it "solves a consistent GF(3) system and returns a verified Boolean model" ->
    equations = [
      [[0, 1, 2, 3], [1, 1, 1, 1], 0],
      [[0, 1, 2, 4], [1, 2, 1, 2], 1],
      [[1, 2, 3, 4], [2, 1, 2, 1], 2]
    ]
    formula = wassat_parse_cnf_native(ternary_affine_cnf(5, equations))
    result = wassat_ternary_affine_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(result["equations"]).to eq(3)
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "recognizes independently of clause and literal order" ->
    equations = [
      [[0, 1, 2, 3], [1, 2, 2, 1], 2],
      [[1, 2, 3, 4], [2, 1, 1, 2], 0]
    ]
    # Alternate the two equation blocks clause by clause and reverse every
    # quad. This exercises the general Hash lookup path behind the contiguous
    # block cache as well as the literal-sort path.
    text = ternary_affine_interleave_cnf(
      ternary_affine_cnf(5, equations), 5, equations.size
    )
    formula = wassat_parse_cnf_native(text)
    result = wassat_ternary_affine_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "proves an inconsistent affine system exactly" ->
    equations = [
      [[0, 1, 2, 3], [1, 1, 1, 1], 0],
      [[0, 1, 2, 4], [1, 1, 1, 1], 0],
      [[0, 1, 3, 4], [0, 0, 1, 2], 1]
    ]
    formula = wassat_parse_cnf_native(ternary_affine_cnf(5, equations))
    expect(ternary_affine_brute_status(5, equations)).to eq(-1)
    result = wassat_ternary_affine_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(-1)

  it "rejects a 54-pattern block that is not affine" ->
    equations = [[[0, 1, 2, 3], [1, 1, 1, 1], 0]]
    text = ternary_affine_cnf(4, equations)
    # Swap one forbidden tuple for one allowed tuple without changing the
    # header or block cardinality.
    text = text.replace("-1 -4 -7 -11 0", "-1 -4 -7 -10 0")
    result = wassat_ternary_affine_solve(wassat_parse_cnf_native(text))
    expect(result["recognized"]).to eq(false)

  it "rejects a malformed exact-one shell" ->
    equations = [[[0, 1, 2, 3], [1, 1, 1, 1], 0]]
    text = ternary_affine_cnf(4, equations)
    text = text.replace("-1 -2 0", "-1 -5 0")
    result = wassat_ternary_affine_solve(wassat_parse_cnf_native(text))
    expect(result["recognized"]).to eq(false)

  it "recognizes every canonical four-variable affine equation" ->
    sound = true
    code = 1
    while code < 81
      q = code
      coeff = []
      i = 0
      while i < 4
        coeff.push(q % 3)
        q /= 3
        i += 1
      first = 0
      i = 0
      while i < 4 && first == 0
        first = coeff[i]
        i += 1
      if first == 1
        rhs = 0
        while rhs < 3
          equations = [[[0, 1, 2, 3], coeff, rhs]]
          formula = wassat_parse_cnf_native(
            ternary_affine_cnf(4, equations)
          )
          result = wassat_ternary_affine_solve(formula)
          sound = false unless result["recognized"] && result["status"] == 1
          sound = false unless wassat_model_satisfies?(
            formula, result["model"]
          )
          rhs += 1
      code += 1
    expect(sound).to eq(true)

  it "matches brute force for every rhs vector of an overdetermined system" ->
    templates = [
      [[0, 1, 2, 3], [1, 1, 1, 1]],
      [[0, 1, 2, 4], [1, 2, 1, 2]],
      [[0, 1, 2, 5], [2, 1, 2, 1]],
      [[0, 1, 3, 4], [1, 1, 2, 2]],
      [[0, 2, 4, 5], [2, 1, 1, 2]],
      [[1, 2, 3, 5], [1, 2, 2, 1]],
      [[2, 3, 4, 5], [2, 2, 1, 1]]
    ]
    limit = 1
    i = 0
    while i < templates.size
      limit *= 3
      i += 1
    sound = true
    state = 0
    while state < limit
      q = state
      equations = []
      templates.each -> (template)
        equations.push([template[0], template[1], q % 3])
        q /= 3
      formula = wassat_parse_cnf_native(
        ternary_affine_cnf(6, equations)
      )
      result = wassat_ternary_affine_solve(formula)
      expect_status = ternary_affine_brute_status(6, equations)
      sound = false unless result["recognized"]
      sound = false unless result["status"] == expect_status
      if result["status"] == 1
        sound = false unless wassat_model_satisfies?(
          formula, result["model"]
        )
      state += 1
    expect(sound).to eq(true)

  it "uses a verified affine SAT model in proof mode without publishing a proof" ->
    bin = env("WASSAT_TEST_BIN")
    expect(bin == nil).to eq(false)
    equations = [
      [[0, 1, 2, 3], [1, 1, 1, 1], 0],
      [[0, 1, 2, 4], [1, 2, 1, 2], 1]
    ]
    input = "/tmp/wassat-ternary-affine-proof-mode.cnf"
    proof = "/tmp/wassat-ternary-affine-proof-mode.drat"
    output = "/tmp/wassat-ternary-affine-proof-mode.out"
    expect(write_file(input, ternary_affine_cnf(5, equations))).to eq(true)
    z = ccall("__w_unlink", proof)
    cmd = "(" + bin + " " + input + " --drat " + proof + " > " + output + " 2>&1); test $? -eq 10"
    ok = system(cmd)
    expect(ok).to eq(true)
    text = read_file(output)
    expect(text.include?("s SATISFIABLE")).to eq(true)
    expect(text.include?("c mode: proof (exact ternary affine GF(3) model)")).to eq(true)
    expect(file?(proof)).to eq(false)

spec_summary
